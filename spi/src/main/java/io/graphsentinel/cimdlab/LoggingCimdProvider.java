package io.graphsentinel.cimdlab;

import org.jboss.logging.Logger;
import org.keycloak.models.ClientModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.AbstractClientIdMetadataDocumentExecutor.FetchOperation;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.AbstractClientIdMetadataDocumentExecutor.OIDCClientRepresentationWithCacheControl;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.ClientIdMetadataDocumentExecutor;
import org.keycloak.protocol.oauth2.cimd.provider.AbstractPersistentClientIdMetadataDocumentProvider;
import org.keycloak.representations.idm.ClientRepresentation;
import org.keycloak.services.clientpolicy.ClientPolicyException;

/**
 * A CIMD provider that behaves like the stock persistent provider and logs when each of its two
 * hooks is entered. It exists to answer one question (checks/03-provider-hook.sh): can a custom
 * provider reach a document that fails to parse?
 *
 * <p>{@code determineFetchOperation} receives only the client_id, before the fetch.
 * {@code createClientMetadata} is the only provider method that receives the document. Measured:
 * for a document that fails to parse, the first is called and the second is not.
 *
 * <p>Nothing else is changed: the client metadata is handled as by the stock persistent provider.
 */
public class LoggingCimdProvider
        extends AbstractPersistentClientIdMetadataDocumentProvider<ClientIdMetadataDocumentExecutor.Configuration> {

    private static final Logger LOG = Logger.getLogger(LoggingCimdProvider.class);

    public LoggingCimdProvider(KeycloakSession session) {
        super(session);
    }

    @Override
    public Logger getLogger() {
        return LOG;
    }

    @Override
    public ClientIdMetadataDocumentExecutor.Configuration getConfiguration() {
        return configuration;
    }

    @Override
    public void setConfiguration(ClientIdMetadataDocumentExecutor.Configuration configuration) {
        this.configuration = configuration;
    }

    /** Least privilege, as in the stock persistent provider. */
    @Override
    public void augmentClientMetadata(ClientRepresentation clientRep) {
        clientRep.setFullScopeAllowed(false);
    }

    @Override
    public FetchOperation determineFetchOperation(String clientId) {
        LOG.infof("[logging-cimd] ENTRY determineFetchOperation clientId=%s", clientId);
        return super.determineFetchOperation(clientId);
    }

    @Override
    public ClientModel createClientMetadata(OIDCClientRepresentationWithCacheControl rep)
            throws ClientPolicyException {
        LOG.infof("[logging-cimd] ENTRY createClientMetadata clientId=%s",
                rep.getOidcClientRepresentation() == null ? "(null)" : rep.getOidcClientRepresentation().getClientId());
        return super.createClientMetadata(rep);
    }
}
