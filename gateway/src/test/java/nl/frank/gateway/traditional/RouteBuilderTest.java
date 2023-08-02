package nl.frank.gateway.traditional;

import com.fasterxml.jackson.databind.ObjectMapper;
import nl.frank.gateway.domain.RouteDefinition;
import nl.frank.gateway.domain.Timeout;
import org.junit.jupiter.api.Test;

import java.util.List;

public class RouteBuilderTest {

	private final ObjectMapper objectMapper = new ObjectMapper();
	private final RouteBuilder routeBuilder = new RouteBuilder(objectMapper);
	@Test
	void testTraditionalRouteBuilder() {
		RouteDefinition testRouteDefinition = RouteDefinition.builder()
			.name("testRoute")
			.desc("this is a test route")
			.uri("/test")
			.uris(List.of("/test", "/another-test"))
			.host("example.com")
			.hosts(List.of("example.com", "test.example.com"))
			.remoteAddr("http://backend.example.com")
			.remoteAddrs(List.of("http://backend.example.com", "http://backend-2.example.com"))
			.methods(List.of("GET", "POST", "PUT"))
			.priority("priority")
			.vars(List.of("var1", "var2"))
			.filterFunc("")
			.plugins(List.of("plugin1", "plugin2"))
			.script("")
			.upstreamId("upstream1")
			.pluginConfigId("plugin1")
			.labels(List.of("label1", "label2"))
			.timeout(new Timeout(1,2,3))
			.enableWebsocket(false)
			.status(true)
			.createTime(System.currentTimeMillis())
			.updateTime(System.currentTimeMillis())
			.build();

		String rawTraditionalRouteDefiniton = routeBuilder.applyRoute(testRouteDefinition);
		System.out.println(rawTraditionalRouteDefiniton);
	}
}
