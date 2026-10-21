package com.example.gcspubsub.pubsub;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * Receives GCS object notifications delivered by a Pub/Sub push subscription.
 * Returning 2xx acks the message; anything else makes Pub/Sub retry.
 */
@RestController
public class PubSubPushController {

	private static final Logger log = LoggerFactory.getLogger(PubSubPushController.class);

	@PostMapping("/pubsub/push")
	public ResponseEntity<Void> receive(@RequestBody PubSubPushRequest request) {
		PubSubPushRequest.Message message = request.message();
		if (message == null) {
			log.warn("Received push request without a message: {}", request);
			// Ack anyway: a malformed envelope will never succeed on retry.
			return ResponseEntity.noContent().build();
		}

		Map<String, String> attributes = message.attributes() == null ? Map.of() : message.attributes();
		String data = message.data() == null ? ""
				: new String(Base64.getDecoder().decode(message.data()), StandardCharsets.UTF_8);

		log.info("Pub/Sub message received: messageId={}, subscription={}, eventType={}, bucket={}, object={}",
				message.messageId(), request.subscription(), attributes.get("eventType"), attributes.get("bucketId"),
				attributes.get("objectId"));
		log.info("Message attributes: {}", attributes);
		log.info("Message data: {}", data);

		return ResponseEntity.noContent().build();
	}

}
