package nl.frank.gateway.domain;

public enum Scheme {
	HTTP("http"),
	HTTPS("https"),
	GRPC("grpc"),
	GRPCS("grpcs"),
	// below is only valid for stream proxy
	TCP("tcp"),
	UDP("udp"),
	TLS("tls");

	private String name;

	public String getName() {
		return name;
	}

	Scheme(String name) {
		this.name = name;
	}
}
