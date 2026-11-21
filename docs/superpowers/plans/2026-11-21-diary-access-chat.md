# Diary Access and Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Give patients control of professional access to each diary and let either chat participant remove messages they sent from both histories.

**Architecture:** PostgreSQL stores diary grants and message deletion markers. Go enforces authorization for records, attachments and history. Flutter uses the same access sheet from the editor and list and opens shared diary references through the authorized diary API.

**Tech Stack:** Flutter/Riverpod, Go REST/WebSocket, PostgreSQL.

**Spec:** Eight screenshots and feature requirements supplied on 21 November 2026. The user approved additive schema and API changes after the impact review.

- [x] Add migrations 042 and 043 for recipient grants and deleted messages. Preserve existing consent and relationship checks on legacy broad sharing. New diary creation uses private access.
- [x] Implement owner-only recipient GET/PUT/DELETE and authorized diary detail. Verify that portal, timeline and private media checks reject revoked recipients. Existing snapshot chat records remain readable and can be deleted by their sender.
- [x] Use the recipient state in Diary history and Add/Edit Diary. Saving a draft for sharing must finish successfully before granting access. Verify add, revoke, retry and account change.
- [x] Use diary ID references for newly sent chat cards. Keep the compact preview and full sheet, with current recipient authorization and realtime refresh. Verify a denied detail never falls back to snapshot content.
- [x] Delete own messages only via authenticated DELETE, retain the deleted ID for idempotent retry, and remove private attachment access. Propagate by WebSocket and reconcile upon reconnect. Cover both roles, cancellation, errors, and stale history.
- [ ] Regenerate API docs and verify Flutter, Go, database migrations and deployment gates before publishing backend, web and signed APK.
