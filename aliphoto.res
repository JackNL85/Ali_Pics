package aliphoto.rest;

import static java.nio.file.StandardOpenOption.APPEND;
import static java.nio.file.StandardOpenOption.CREATE;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Stream;

import javax.servlet.http.HttpServletRequest;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.google.common.cache.Cache;
import com.google.common.cache.CacheBuilder;
import com.mashape.unirest.http.Unirest;
import com.mashape.unirest.http.exceptions.UnirestException;

@RestController
public class GetRealPhotosController {
	private static final String FEEDBACK_API_URL = "https://feedback.aliexpress.com/display/productEvaluation.htm";
	private static Logger logger = LoggerFactory.getLogger(GetRealPhotosController.class);
	private ExecutorService fileWriterTh = Executors.newFixedThreadPool(1);
	private Cache<String, String> lastSearched = CacheBuilder.newBuilder().maximumSize(10).build();

	@CrossOrigin(origins = "*")
	@RequestMapping("/getRealPhotos")
	public List<String> getRealPhotos(HttpServletRequest request, @RequestParam(value = "productUrl") String url) {
		asyncSaveUrlToFile(request, url);

		ConcurrentHashMap<String, Object> feedBackParams = new ConcurrentHashMap<>();
		try {
			populateProductParamsFromPage(url, feedBackParams);
		} catch (UnirestException e) {
			logger.error("Error while parsing page={}", url);
			throw new RuntimeException("Server error");
		}
		ArrayList<String> photoUrls = getPhotos(url, feedBackParams);
		if (!photoUrls.isEmpty()) {
			lastSearched.put(url, photoUrls.get(0));
		}
		return photoUrls;
	}

	@CrossOrigin(origins = "*")
	@RequestMapping("/getLastProducts")
	public Map<String, String> getLastProducts(HttpServletRequest request) {
		return lastSearched.asMap();
	}

	private void asyncSaveUrlToFile(HttpServletRequest request, String url) {
		fileWriterTh.execute(() -> {
			try {
				Files.write(Paths.get("./urls.txt"),
						(request.getRemoteAddr() + "," + new Date() + "," + url + "\n").getBytes(), APPEND, CREATE);
			} catch (Exception e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
		});
	}

	private ArrayList<String> getPhotos(String url, ConcurrentHashMap<String, Object> feedBackParams) {
		ArrayList<String> photos = new ArrayList<>();
		Document doc;
		try {
			doc = Jsoup.parse(Unirest.post(FEEDBACK_API_URL).queryString(feedBackParams).asString().getBody());
			int maxPage = getMaxPage(doc);
			int crtPage = 1;
			do {
				Elements elements = doc.select("li[class$=pic-view-item]");
				for (Element el : elements) {
					photos.add(el.select("img").get(0).attr("src"));
				}
				crtPage++;
				feedBackParams.put("page", crtPage);
				doc = Jsoup.parse(Unirest.post(FEEDBACK_API_URL).queryString(feedBackParams).asString().getBody());
				logger.debug("For url={} processing page={}", url, crtPage);
			} while (crtPage <= maxPage);
		} catch (UnirestException e) {
			logger.error("Feedback api call error", e);
			return photos;
		}
		return photos;
	}

	private int getMaxPage(Document doc) {
		int maxPage = 0;
		try {
			maxPage = Integer.valueOf(
					doc.select("div[id$=simple-pager]").first().select("label").first().toString().split("/")[1]
							.split("<")[0]);
			if (maxPage > 10)
				return 10;
		} catch (Exception ex) {
			// TODO fix this
		}
		return maxPage;
	}

	private void populateProductParamsFromPage(String url, ConcurrentHashMap<String, Object> params)
			throws UnirestException {
		Stream.of((Unirest.get(url).asString().getBody().split("thesrc=")[1].split(">")[0].split("\\?")[1].split("&")))
				.forEach(el -> {
					String[] keyValue = el.split("=");
					if (keyValue.length == 2 && !keyValue[0].trim().isEmpty() && !keyValue[1].trim().isEmpty()) {
						params.put(keyValue[0].trim(), keyValue[1].trim());
					}
				});

		params.put("page", "1");
		params.put("withPictures", "true");
	}

}
