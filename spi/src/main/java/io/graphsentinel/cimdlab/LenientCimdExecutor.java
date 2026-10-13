package io.graphsentinel.cimdlab;

import java.net.URI;

import org.jboss.logging.Logger;
import org.keycloak.http.simple.SimpleHttp;
import org.keycloak.http.simple.SimpleHttpResponse;
import org.keycloak.models.KeycloakSession;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.ClientIdMetadataDocumentExecutor;
import org.keycloak.protocol.oauth2.cimd.clientpolicy.executor.ClientIdMetadataDocumentExecutorFactoryProviderConfig;
import org.keycloak.protocol.oauth2.cimd.provider.ClientIdMetadataDocumentProvider;
import org.keycloak.representations.oidc.OIDCClientRepresentation;
import org.keycloak.services.clientpolicy.ClientPolicyException;
import org.keycloak.util.JsonSerialization;

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

    private final long upperLimitBytes;

    public LenientCimdExecutor(KeycloakSession session,
                               ClientIdMetadataDocumentExecutorFactoryProviderConfig config) {
        super(session, config);
        this.upperLimitBytes = config == null
                ? ClientIdMetadataDocumentExecutorFactoryProviderConfig.DEFAULT_CONFIG_UPPER_LIMIT_METADATA_BYTES
                : config.getUpperLimitMetadataBytes();
    }

    @Override
    protected Logger getLogger() {
        return LOG;
    }

    @Override
    public String getProviderId() {
        return LenientCimdExecutorFactory.PROVIDER_ID;
    }

    @Override
    protected OIDCClientRepresentationWithCacheControl fetchClientMetadata(
            URI clientIdUri, boolean allowHttpScheme, ClientIdMetadataDocumentProvider provider)
            throws ClientPolicyException {
        // The lenient mapper is handed to SimpleHttp, so the fetch, the size cap and the
        // deserialisation all stay on Keycloak's own code path. The single deviation is the
        // mapper's FAIL_ON_UNKNOWN_PROPERTIES flag.
        OIDCClientRepresentation rep;
        String cacheControl;
        try (SimpleHttpResponse res = SimpleHttp.create(session)
                .withObjectMapper(LENIENT)
                .withMaxConsumedResponseSize(upperLimitBytes)
                .doGet(clientIdUri.toString())
                .acceptJson()
                .asResponse()) {
            int status = res.getStatus();
            if (status != 200) {
                // Stock contract preserved: a non-200 is a fetch failure, not a parse failure.
                throw invalidClientIdMetadata("client metadata fetch returned HTTP " + status);
            }
            cacheControl = res.getFirstHeader("Cache-Control");
            // Malformed JSON still fails here. Leniency covers UNKNOWN properties only.
            rep = (OIDCClientRepresentation) res.asJson(OIDCClientRepresentation.class);
        } catch (ClientPolicyException e) {
            throw e;
        } catch (Exception e) {
            LOG.warnf("[lenient-cimd] could not obtain client metadata from %s: %s",
                    clientIdUri, e.getClass().getSimpleName());
            throw invalidClientIdMetadata("client metadata fetch failed");
        }
        if (rep == null) {
            throw invalidClientIdMetadata("client metadata document could not be parsed");
        }

        LOG.infof("[lenient-cimd] parsed %s leniently; inherited validation still applies", clientIdUri);
        return new OIDCClientRepresentationWithCacheControl(
                rep, new ClientMetadataCacheControl(cacheControl, 0, 0));
    }
}
