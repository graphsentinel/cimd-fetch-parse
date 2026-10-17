package io.graphsentinel.cimdlab;

import java.io.IOException;
import java.net.URI;

import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.Response;

import org.jboss.logging.Logger;
import org.keycloak.OAuthErrorException;
import org.keycloak.http.simple.SimpleHttp;
import org.keycloak.http.simple.SimpleHttpResponse;
import org.keycloak.models.ClientModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.ClientIdMetadataDocumentExecutor;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.ClientIdMetadataDocumentExecutorFactoryProviderConfig;
import org.keycloak.protocol.oauth2.cimd.provider.ClientIdMetadataDocumentProvider;
import org.keycloak.representations.oidc.OIDCClientRepresentation;
import org.keycloak.services.clientpolicy.ClientPolicyException;
import org.keycloak.util.JsonSerialization;

import com.fasterxml.jackson.core.JsonParseException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * The narrow intervention: tolerate unknown properties in a CIMD document, nothing else.
 *
 * <p><b>What this exists to answer.</b> Five of the eight published CIMD client identities we
 * measured are refused by stock Keycloak 26.7.0 and 26.8.0 because they carry a property outside
 * {@code OIDCClientRepresentation}'s known set. The operator cannot change those documents;
 * OpenAI, opencode and goose publish them. The question is whether a deployment can accept them
 * <em>without</em> becoming lenient about everything else.
 *
 * <p><b>Where the intervention has to live.</b> Measured (checks/03-provider-hook.sh): for a document that fails
 * to parse, the CIMD <em>provider</em> is consulted at {@code determineFetchOperation}, which
 * receives only the client_id, and {@code createClientMetadata} — the only provider method that
 * sees the document — is never reached. On this path the provider hook cannot reach the document; the executor can:
 * {@code fetchClientMetadata} is {@code protected}.
 *
 * <p><b>The surgical boundary.</b> This class overrides <b>only</b> the fetch and parse. It
 * extends the concrete {@link ClientIdMetadataDocumentExecutor}, so that class's
 * {@code validateClientMetadata} — the client_id match, the URI property checks, the required
 * properties, the trusted-domain rules — is inherited unchanged and still runs on whatever this
 * method returns. Leniency is confined to one Jackson flag on one mapper used in one place.
 *
 * <p><b>Not a production fix.</b> This is an experiment that answers "can you be lenient about
 * unknown fields without loosening the rest". If upstream resolves keycloak#51236/#51235 this
 * becomes unnecessary.
 */
public class LenientCimdExecutor extends ClientIdMetadataDocumentExecutor {

    private static final Logger LOG = Logger.getLogger(LenientCimdExecutor.class);

    /** The one deviation from stock: unknown properties are tolerated. Nothing else changes. */
    private static final ObjectMapper LENIENT = JsonSerialization.mapper
            .copy()
            .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);

    /** Same text as the upstream fix (keycloak PR #51235), so callers see the same error either way. */
    public static final String ERR_METADATA_PARSE_FAILED =
            "Invalid Client Metadata: cannot be parsed as a client metadata document.";

    public LenientCimdExecutor(KeycloakSession session,
                               ClientIdMetadataDocumentExecutorFactoryProviderConfig config) {
        super(session, config);
    }

    @Override
    protected Logger getLogger() {
        return LOG;
    }

    @Override
    public String getProviderId() {
        return LenientCimdExecutorFactory.PROVIDER_ID;
    }

    /**
     * Stock {@code fetchClientMetadata} (26.7.0 and 26.8.0 are identical) with one change: the body is parsed by the
     * lenient mapper, and a body that cannot be parsed is reported as a parse failure, not a fetch failure. Everything
     * else follows stock: 200 required on the first fetch, 200 or 304 on an update, 304 only extends the cache expiry,
     * the configured minimum and maximum cache times, {@code augmentClientOIDC}. checks/11-executor-parity.sh compares
     * the two executors on these paths.
     */
    @Override
    @SuppressWarnings({"rawtypes", "unchecked"}) // the overridden method declares the raw provider type
    protected OIDCClientRepresentationWithCacheControl fetchClientMetadata(
            URI clientIdUri, boolean isUpdate, ClientIdMetadataDocumentProvider provider)
            throws ClientPolicyException {
        String clientId = clientIdUri.toString();
        try (SimpleHttpResponse res = SimpleHttp.create(session)
                .withMaxConsumedResponseSize(providerConfig.getUpperLimitMetadataBytes())
                .doGet(clientId)
                .asResponse()) {
            int status = res.getStatus();
            if (!isUpdate && status != Response.Status.OK.getStatusCode()) {
                LOG.warnf("[lenient-cimd] first fetch of client metadata failed: %s answered HTTP %d", clientId, status);
                throw invalidClientIdMetadata(ERR_METADATA_FETCH_FAILED);
            }
            if (isUpdate && status != Response.Status.OK.getStatusCode()
                    && status != Response.Status.NOT_MODIFIED.getStatusCode()) {
                LOG.warnf("[lenient-cimd] update fetch of client metadata failed: %s answered HTTP %d", clientId, status);
                throw invalidClientIdMetadata(ERR_METADATA_FETCH_FAILED);
            }
            ClientMetadataCacheControl cacheControl = new ClientMetadataCacheControl(
                    res.getFirstHeader(HttpHeaders.CACHE_CONTROL),
                    providerConfig.getMinCacheTime(), providerConfig.getMaxCacheTime());
            if (isUpdate && status == Response.Status.NOT_MODIFIED.getStatusCode()) {
                ClientModel client = session.getContext().getRealm().getClientByClientId(clientId);
                provider.setCacheExpiryTimeToClientMetadata(client, cacheControl.getCacheExpiryTimeInSec());
                return null;
            }
            OIDCClientRepresentation rep;
            try {
                rep = LENIENT.readValue(res.asString(), OIDCClientRepresentation.class);
            } catch (JsonProcessingException e) {
                // the exception class name stays in the log line: checks read the server's reason from it
                LOG.warnf("[lenient-cimd] could not parse client metadata from %s: %s: %s", clientId,
                        e instanceof JsonParseException ? "JsonParseException" : "JsonMappingException",
                        e.getOriginalMessage());
                throw invalidClientIdMetadata(ERR_METADATA_PARSE_FAILED);
            }
            if (rep == null) {
                throw invalidClientIdMetadata(ERR_METADATA_PARSE_FAILED);
            }
            augmentClientOIDC(rep);
            LOG.infof("[lenient-cimd] parsed %s leniently; inherited validation still applies", clientId);
            return new OIDCClientRepresentationWithCacheControl(rep, cacheControl);
        } catch (IOException e) {
            LOG.warnf("[lenient-cimd] could not obtain client metadata from %s: %s", clientId, e.getClass().getSimpleName());
            throw new ClientPolicyException(OAuthErrorException.INVALID_REQUEST, ERR_METADATA_FETCH_FAILED);
        }
    }
}
