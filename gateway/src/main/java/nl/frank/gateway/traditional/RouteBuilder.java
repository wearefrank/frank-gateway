package nl.frank.gateway.traditional;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import nl.frank.gateway.domain.Route;
import nl.frank.gateway.domain.RouteDefinition;

@RequiredArgsConstructor
public class RouteBuilder implements Route {

	private final ObjectMapper objectMapper;

	// Transform from the common RouteDefinition to the deployment specific RouteDefinition and
	// Generate the RouteDefinition in the correct format for traditional this is JSON
	@Override
	public String applyRoute(RouteDefinition routeDefinition) {
		TraditionalRouteDefinition traditionalRouteDefinition = TraditionalRouteDefinition.builder()
			.name(routeDefinition.name())
			.desc(routeDefinition.desc())
			.uri(routeDefinition.uri())
			.uris(routeDefinition.uris())
			.host(routeDefinition.host())
			.hosts(routeDefinition.hosts())
			.remoteAddr(routeDefinition.remoteAddr())
			.remoteAddrs(routeDefinition.remoteAddrs())
			.methods(routeDefinition.methods())
			.priority(routeDefinition.priority())
			.vars(routeDefinition.vars())
			.filterFunc(routeDefinition.filterFunc())
			.plugins(routeDefinition.plugins())
			.script(routeDefinition.script())
			.upstreamId(routeDefinition.upstreamId())
			.pluginConfigId(routeDefinition.pluginConfigId())
			.labels(routeDefinition.labels())
			.timeout(routeDefinition.timeout())
			.enableWebsocket(routeDefinition.enableWebsocket())
			.status(routeDefinition.status())
			.createTime(routeDefinition.createTime())
			.updateTime(routeDefinition.updateTime())
			.build();

		try {
			return objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(traditionalRouteDefinition);
		} catch (JsonProcessingException e) {
			throw new RuntimeException(e);
		}
	}
}
