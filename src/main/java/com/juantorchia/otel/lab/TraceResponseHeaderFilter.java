package com.juantorchia.otel.lab;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
class TraceResponseHeaderFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        SpanContext context = Span.current().getSpanContext();
        if (context.isValid()) {
            response.setHeader("X-Trace-Id", context.getTraceId());
            response.setHeader("X-Span-Id", context.getSpanId());
        }
        filterChain.doFilter(request, response);
    }
}
