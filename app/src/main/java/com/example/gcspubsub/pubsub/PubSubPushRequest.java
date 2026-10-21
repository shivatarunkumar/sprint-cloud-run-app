package com.example.gcspubsub.pubsub;

import java.util.Map;

/**
 * Envelope Pub/Sub sends to a push endpoint.
 * See https://cloud.google.com/pubsub/docs/push#receive_push
 */
public record PubSubPushRequest(Message message, String subscription) {

	/**
	 * For GCS notifications, {@code data} is the base64-encoded object metadata JSON and
	 * {@code attributes} carry eventType, bucketId, objectId, etc.
	 */
	public record Message(String data, Map<String, String> attributes, String messageId, String publishTime) {
	}

}
