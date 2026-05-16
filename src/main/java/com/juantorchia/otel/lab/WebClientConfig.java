package com.juantorchia.otel.lab;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
class WebClientConfig {

    @Bean
    WebClient downstreamClient(@Value("${server.port:8080}") int port) {
        return WebClient.builder()
                .baseUrl("http://localhost:" + port)
                .build();
    }
}
