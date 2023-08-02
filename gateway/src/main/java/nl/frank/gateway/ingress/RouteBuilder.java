package nl.frank.gateway.ingress;

import io.fabric8.kubernetes.api.model.*;
import io.fabric8.kubernetes.client.utils.Serialization;
import nl.frank.gateway.domain.Route;
import nl.frank.gateway.domain.RouteDefinition;
import org.apache.apisix.v2.ApisixRoute;
import org.apache.apisix.v2.ApisixRouteSpec;
import org.apache.apisix.v2.apisixroutespec.HttpBuilder;
import org.apache.apisix.v2.apisixroutespec.http.BackendsBuilder;
import org.apache.apisix.v2.apisixroutespec.http.MatchBuilder;

import java.util.List;

// Transform from the common RouteDefinition to the deployment specific RouteDefinition and
// Generate the RouteDefinition in the correct format for ingress this is a Kubernetes Custom Resource
public class RouteBuilder implements Route {

	@Override
	public String applyRoute(RouteDefinition routeDefinition) {
		ApisixRoute apisixRoute = new ApisixRoute();
		apisixRoute.setMetadata(generateMetaData(routeDefinition.name()));
		apisixRoute.setSpec(generateApisixRouteSpec(routeDefinition));

		return Serialization.asYaml(apisixRoute);
	}

	private ApisixRouteSpec generateApisixRouteSpec(RouteDefinition routeDefinition) {
		ApisixRouteSpec apisixRouteSpec = new ApisixRouteSpec();
		MatchBuilder match = new MatchBuilder();
		routeDefinition.uris().forEach(match::addToPaths);

		BackendsBuilder backendsBuilder = new BackendsBuilder();
		backendsBuilder.withServiceName("foo-service"); //TODO need to come from the upstream
		backendsBuilder.withServicePort(new IntOrString("8080")); //TODO need to come from the upstream

		HttpBuilder httpSpecBuilder = new HttpBuilder();
		httpSpecBuilder.withMatch(match.build());
		httpSpecBuilder.withBackends(backendsBuilder.build());
		apisixRouteSpec.setHttp(List.of(httpSpecBuilder.build()));
		return apisixRouteSpec;
	}

	private ObjectMeta generateMetaData(String name) {

		ObjectMetaBuilder metaBuilder = new ObjectMetaBuilder();
		metaBuilder.withName(name);
		return metaBuilder.build();
	}
}
