package com.example.gcspubsub.pubsub;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class PubSubPushControllerTests {

	private final MockMvc mockMvc = MockMvcBuilders.standaloneSetup(new PubSubPushController()).build();

	@Test
	void acksGcsNotification() throws Exception {
		String data = Base64.getEncoder()
			.encodeToString("{\"name\":\"hello.txt\",\"bucket\":\"my-bucket\"}".getBytes(StandardCharsets.UTF_8));
		String body = """
				{
				  "message": {
				    "data": "%s",
				    "attributes": {"eventType": "OBJECT_FINALIZE", "bucketId": "my-bucket", "objectId": "hello.txt"},
				    "messageId": "123",
				    "publishTime": "2026-10-21T10:00:00Z"
				  },
				  "subscription": "projects/p/subscriptions/s"
				}
				""".formatted(data);

		mockMvc.perform(post("/pubsub/push").contentType(MediaType.APPLICATION_JSON).content(body))
			.andExpect(status().isNoContent());
	}

	@Test
	void acksEnvelopeWithoutMessage() throws Exception {
		mockMvc.perform(post("/pubsub/push").contentType(MediaType.APPLICATION_JSON).content("{}"))
			.andExpect(status().isNoContent());
	}

}
