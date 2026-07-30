FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/malva-api ./cmd/api

FROM alpine:3.21
RUN addgroup -S malva && adduser -S malva -G malva
USER malva
COPY --from=build /out/malva-api /usr/local/bin/malva-api
EXPOSE 8080
ENTRYPOINT ["malva-api"]
