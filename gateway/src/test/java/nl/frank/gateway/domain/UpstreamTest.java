package nl.frank.gateway.domain;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

public class UpstreamTest {

	@Test
	void testUpstream_invalidTargetsServiceNameAndNodes() {

		Exception exception = assertThrows(RuntimeException.class, () -> {
			Upstream.builder()
				.serviceName("testService")
				.discoveryType(DiscoveryType.KUBERNETES)
				.nodes(List.of("node1"))
				.build();
		});

		String expectedMessage = "[Either one of serviceName or node must exist, they cannot exist both]";
		String actualMessage = exception.getMessage();

		assertTrue(actualMessage.contains(expectedMessage));
	}

	@Test
	void testUpstream_invalidTargetsNoServiceNameAndNodes() {
		Exception exception = assertThrows(RuntimeException.class, () -> {
			Upstream.builder()
				.build();
		});

		String expectedMessage = "[Either one of serviceName or node must exist]";
		String actualMessage = exception.getMessage();

		assertTrue(actualMessage.contains(expectedMessage));
	}

	@Test
	void testUpstream_invalidTargetsServiceNameAndNoDiscoveryType() {
		Exception exception = assertThrows(RuntimeException.class, () -> {
			Upstream.builder()
				.serviceName("testService")
				.build();
		});

		String expectedMessage = "[When using serviceName discoveryType must be provided]";
		String actualMessage = exception.getMessage();

		assertTrue(actualMessage.contains(expectedMessage));
	}

	@Test
	void testUpstream_invalidTargetsDiscoveryTypeAndNoServiceName() {
		Exception exception = assertThrows(RuntimeException.class, () -> {
			Upstream.builder()
				.discoveryType(DiscoveryType.KUBERNETES)
				.build();
		});

		String expectedMessage = "[Either one of serviceName or node must exist, When using serviceName discoveryType must be provided]";
		String actualMessage = exception.getMessage();

		assertTrue(actualMessage.contains(expectedMessage));
	}

	@Test
	void testUpstream_validWithNodes() {

		Upstream testUpstream = Upstream.builder()
			.nodes(List.of("node1"))
			.build();

		assertEquals(1, testUpstream.getNodes().size());
		assertEquals("node1", testUpstream.getNodes().get(0));
	}

	@Test
	void testUpstream_validWithServiceName() {

		Upstream testUpstream = Upstream.builder()
			.serviceName("testService")
			.discoveryType(DiscoveryType.EUREKA)
			.build();

		assertEquals("testService", testUpstream.getServiceName());
		assertEquals(DiscoveryType.EUREKA, testUpstream.getDiscoveryType());
	}

	@Test
	void testUpstream_hashOnWithInvalidType() {
		Exception exception = assertThrows(RuntimeException.class, () -> {
			Upstream.builder()
				.type(UpstreamType.ROUND_ROBIN)
				.nodes(List.of("node1"))
				.hashOn(HashOn.COOKIE)
				.build();
		});

		String expectedMessage = "[When using hashOn type must be 'chash']";
		String actualMessage = exception.getMessage();

		assertTrue(actualMessage.contains(expectedMessage));
	}

	@Test
	void testUpstream_keyWithInvalidType() {
		Exception exception = assertThrows(RuntimeException.class, () -> {
			Upstream.builder()
				.type(UpstreamType.ROUND_ROBIN)
				.nodes(List.of("node1"))
				.key(UpstreamKey.HOST)
				.build();
		});
		String expectedMessage = "[When using key hashOn type must be 'chash']";
		String actualMessage = exception.getMessage();

		assertTrue(actualMessage.contains(expectedMessage));

	}

	@Test
	void testUpstream_validWithChash() {

		Upstream testUpstream = Upstream.builder()
			.type(UpstreamType.CHASH)
			.serviceName("testService")
			.discoveryType(DiscoveryType.EUREKA)
			.hashOn(HashOn.HEADER)
			.key(UpstreamKey.HOST)
			.build();

		assertEquals("testService", testUpstream.getServiceName());
		assertEquals(DiscoveryType.EUREKA, testUpstream.getDiscoveryType());
	}
}
