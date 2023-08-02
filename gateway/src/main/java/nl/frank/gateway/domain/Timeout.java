package nl.frank.gateway.domain;

public record Timeout(Integer connect, Integer send, Integer read) {
}
