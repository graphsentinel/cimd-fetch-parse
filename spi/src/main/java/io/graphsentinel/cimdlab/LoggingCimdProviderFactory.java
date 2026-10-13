package io.graphsentinel.cimdlab;

import org.keycloak.models.KeycloakSession;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.ClientIdMetadataDocumentExecutor;
import org.keycloak.protocol.oauth2.cimd.provider.AbstractPersistentClientIdMetadataDocumentProviderFactory;
import org.keycloak.protocol.oauth2.cimd.provider.ClientIdMetadataDocumentProvider;

/**
 * Factory for {@link LoggingCimdProvider}. Select it with the Keycloak option
 * {@code --spi-client-policy-executor--client-id-metadata-document--cimd-provider-name=logging-cimd}
 * (the stock provider is {@code persistent-cimd}).
 */
public class LoggingCimdProviderFactory extends AbstractPersistentClientIdMetadataDocumentProviderFactory {

    public static final String PROVIDER_ID = "logging-cimd";

    @Override
    public ClientIdMetadataDocumentProvider<ClientIdMetadataDocumentExecutor.Configuration> create(KeycloakSession session) {
        return new LoggingCimdProvider(session);
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }
}
