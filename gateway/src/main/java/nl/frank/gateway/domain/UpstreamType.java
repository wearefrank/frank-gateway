package nl.frank.gateway.domain;

public enum UpstreamType {
	ROUND_ROBIN("roundrobin"),
	CHASH("chash");

	private String name;

	public String getName() {
		return name;
	}

	UpstreamType(String name) {
		this.name = name;
	}
}
