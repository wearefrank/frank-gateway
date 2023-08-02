package nl.frank.gateway.domain;

public enum HashOn {
	VARS("vars"),
	HEADER("header"),
	COOKIE("cookie"),
	CONSUMER("consumer");

	private String name;

	HashOn(String name) {
		this.name = name;
	}

	public String getName() {
		return name;
	}
}
