package nl.frank.gateway.domain;

public enum UpstreamKey {
	URI("uri"),
	SERVER_NAME("server_name"),
	SERVER_ADDR("server_addr"),
	REQUEST_URI("request_uri"),
	REMOTE_PORT("remote_port"),
	REMOTE_ADDR("remote_addr"),
	QUERY_STRING("query_string"),
	HOST("host"),
	HOSTNAME("hostname"),
	ARG("arg_***");

	private String name;

	public String getName() {
		return name;
	}

	UpstreamKey(String name) {
		this.name = name;
	}
}
