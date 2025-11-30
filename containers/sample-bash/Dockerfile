FROM alpine:3.18

# Install dependencies
RUN apk add --no-cache \
    curl \
    jq \
    bash

WORKDIR /app

# Copy test script
COPY test.sh .

# Make script executable
RUN chmod +x test.sh

# Create non-root user
RUN adduser -u 1001 -D -s /bin/bash testuser
USER testuser

# Run the test script
CMD ["./test.sh"]
