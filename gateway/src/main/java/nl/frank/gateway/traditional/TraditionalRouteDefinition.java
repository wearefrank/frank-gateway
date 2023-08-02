package nl.frank.gateway.traditional;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Builder;
import nl.frank.gateway.domain.Timeout;

import java.util.List;
//This is for now the same as the RouteDefinition, based on the other implementations we need to verify if the RouteDefition needs to change
public record TraditionalRouteDefinition(

	String name,
	String desc,
	String uri,
	List<String> uris,
	String host,
	List<String> hosts,
	@JsonProperty("remote_addr")
	String remoteAddr,
	@JsonProperty("remote_addrs")
	List<String> remoteAddrs,
	List<String> methods,
	String priority,
	List<String> vars,
	@JsonProperty("filter_func")
	String filterFunc,
	List<String> plugins, //TODO need to be a separate Plugin object
	String script,
	String upstream, //TODO needs to be a separate upstream object
	@JsonProperty("upstream_id")
	String upstreamId,
	@JsonProperty("service_id")
	String serviceId,
	@JsonProperty("plugin_config_id")
	String pluginConfigId,
	List<String> labels,
	Timeout timeout,
	@JsonProperty("enable_websocket")
	boolean enableWebsocket,
	boolean status,
	@JsonProperty("create_time")
	Long createTime,
	@JsonProperty("update_time")
	Long updateTime
) {
	@Builder(toBuilder = true)
	public TraditionalRouteDefinition {}
}
