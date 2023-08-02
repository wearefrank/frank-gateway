package nl.frank.gateway.domain;

public enum PassHost {
	PASS("pass"),
	NODE("node"),
	REWRITE("rewrite");

	private String name;

	public String getName() {
		return name;
	}

	PassHost(String name) {
		this.name = name;
	}
}
