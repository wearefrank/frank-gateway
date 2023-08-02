package nl.frank.gateway.ingress;

import nl.frank.gateway.domain.RouteDefinition;
import nl.frank.gateway.domain.Timeout;
import nl.frank.gateway.domain.Upstream;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

public class RouteBuilderTest {

	private final RouteBuilder routeBuilder = new RouteBuilder();
	@Test
	public void testIngressRouteBuilder() {

		Upstream myUpstream = Upstream.builder()
				.name("my awesome upstream")
				.nodes(List.of("b"))
				.build();
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
			.upstream(myUpstream)
			.pluginConfigId("plugin1")
			.labels(List.of("label1", "label2"))
			.timeout(new Timeout(1,2,3))
			.enableWebsocket(false)
			.status(true)
			.createTime(System.currentTimeMillis())
			.updateTime(System.currentTimeMillis())
			.build();

		String routeCR = routeBuilder.applyRoute(testRouteDefinition);
		assertEquals("testRoute", testRouteDefinition.name());
	}
}
