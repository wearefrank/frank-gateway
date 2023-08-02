package nl.frank.gateway.domain;

import lombok.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

// Based on: https://apisix.apache.org/docs/apisix/admin-api/#upstream
@Builder
@Getter
@Value
public class Upstream {
    UpstreamType type;
    List<String> nodes;
    String serviceName;
    DiscoveryType discoveryType;
    HashOn hashOn;
    UpstreamKey key;
    String checks; // TODO needs a separate health check object
    Integer retries;
    Integer retryTimeout;
    Timeout timeout;
    String name;
    String desc;
    PassHost passHost;
    String upstreamHost;
    Scheme scheme;
    Map<String, String> labels;
    Long createTime;
    Long updateTime;
    String tls; // TODO needs a separate TLS object
    String keepAlivePool; // TODO needs a separate keepalive pool object

    @Getter(AccessLevel.NONE)
    @Setter(AccessLevel.NONE)
	List<String> validationViolations;

	public static UpstreamBuilder builder() {
		return new ValidationUpstreamBuilder();
	}

    private static class ValidationUpstreamBuilder extends UpstreamBuilder {

        public Upstream build() {

            super.validationViolations = new ArrayList<>();
            validateTarget();
            validateChashType();

            if(!super.validationViolations.isEmpty()) {
                throw new RuntimeException(super.validationViolations.toString());
            }
            return super.build();
        }

        private void validateTarget() {
            boolean serviceNameExists = super.serviceName != null && !super.serviceName.isEmpty();
			boolean nodesExists = super.nodes != null && !super.nodes.isEmpty();
            boolean discoveryTypeExists = super.discoveryType != null;

            if(serviceNameExists && nodesExists) {
                super.validationViolations.add("Either one of serviceName or node must exist, they cannot exist both");
            }

            if(!serviceNameExists && !nodesExists) {
                super.validationViolations.add("Either one of serviceName or node must exist");
            }

            if(serviceNameExists && !discoveryTypeExists || discoveryTypeExists && !serviceNameExists) {
                super.validationViolations.add("When using serviceName discoveryType must be provided");
            }

        }

        private void validateChashType() {
            boolean isTypeChash = super.type != null && super.type.getName().equals("chash");
            boolean hashOnExists = super.hashOn != null;
            boolean keyExists = super.key != null;

            if(hashOnExists && !isTypeChash) {
                super.validationViolations.add("When using hashOn type must be 'chash'");
            }

            if(keyExists && !isTypeChash) {
                super.validationViolations.add("When using key hashOn type must be 'chash'");
            }
        }
    }
}
