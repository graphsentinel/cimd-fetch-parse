package io.graphsentinel.cimdlab;

import org.keycloak.models.KeycloakSession;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.ClientIdMetadataDocumentExecutorFactory;
import org.keycloak.services.clientpolicy.executor.ClientPolicyExecutorProvider;

/**
 * Registers {@link LenientCimdExecutor} as a selectable client-policy executor.
 *
 * <p>Select it in the realm's client profile by using {@code "executor": "lenient-cimd"}
 * in place of {@code "client-id-metadata-document"}. Configuration keys are inherited.
 */
public class LenientCimdExecutorFactory extends ClientIdMetadataDocumentExecutorFactory {

    public static final String PROVIDER_ID = "lenient-cimd";

    @Override
    public ClientPolicyExecutorProvider create(KeycloakSession session) {
        return new LenientCimdExecutor(session, providerConfig);
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }
}
