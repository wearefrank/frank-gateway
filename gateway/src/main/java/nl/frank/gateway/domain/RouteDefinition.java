package nl.frank.gateway.domain;

import lombok.Builder;

import java.util.List;
//Based on https://apisix.apache.org/docs/apisix/admin-api/#route-api
public record RouteDefinition(
	String name,
	String desc,
	String uri,
	List<String> uris,
	String host,
	List<String> hosts,
	String remoteAddr,
	List<String> remoteAddrs,
	List<String> methods,
	String priority,
	List<String> vars,
	String filterFunc,
	List<String> plugins, //TODO need to be a separate Plugin object
	String script,
	Upstream upstream, //TODO needs to be a separate upstream object
	String upstreamId,
	String serviceId,
	String pluginConfigId,
	List<String> labels,
	Timeout timeout,
	boolean enableWebsocket,
	boolean status,
	Long createTime,
	Long updateTime
) {
	@Builder(toBuilder = true)
	public RouteDefinition {}
}
