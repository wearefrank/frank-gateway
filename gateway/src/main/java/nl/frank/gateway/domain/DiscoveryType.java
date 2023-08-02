package nl.frank.gateway.domain;

public enum DiscoveryType {
	DNS("dns"),
	CONSUL("consul"),
	CONSUL_KV("consul_kv"),
	EUREKA("eureka"),
	KUBERNETES("kubernetes");

	private String name;

	public String getName() {
		return name;
	}

	DiscoveryType(String name) {
		this.name = name;
	}
}
