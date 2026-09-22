/**
 * Contract snapshots. The JSON shape of every output type is what the Flutter
 * client decodes; a change here must be deliberate, with the Dart side updated
 * in the same PR. Run `vitest -u` only when that is true.
 */
import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";
import { toMinuteDetail, toMinuteSummary } from "../../src/minutes/_shared.js";
import { toTagOutput } from "../../src/tags/_shared.js";
import { toUserOutput } from "../../src/users/_shared.js";

const at = Timestamp.fromDate(new Date("2026-09-22T08:41:12.345Z"));

describe("wire shapes", () => {
  it("MinuteSummary", () => {
    expect(
      toMinuteSummary("m1", {
        title: "Standup", iconEmoji: "📝", sourceType: "audio", contentKind: "team_meeting",
        status: "ready", durationSeconds: 900, tagIds: ["t1"], createdAt: at, updatedAt: at,
      }),
    ).toMatchInlineSnapshot(`
      {
        "contentKind": "team_meeting",
        "createdAt": "2026-09-22T08:41:12.345Z",
        "durationSeconds": 900,
        "iconEmoji": "📝",
        "id": "m1",
        "sourceType": "audio",
        "status": "ready",
        "tagIds": [
          "t1",
        ],
        "title": "Standup",
        "updatedAt": "2026-09-22T08:41:12.345Z",
      }
    `);
  });

  it("MinuteDetail", () => {
    expect(
      toMinuteDetail(
        "m1",
        {
          title: "Standup", status: "ready", sourceType: "pdf", createdAt: at, updatedAt: at,
          summary: { title: "S", text: "body", icon: null, sections: [{ title: "A", bullets: ["x"] }] },
          sourcePath: "users/u1/minutes/m1/source/a.pdf", keywords: ["k"], description: "d", summaryLanguage: "en",
          failure: null,
        },
        {
          transcript: { durationSeconds: 1, languageCode: "eng", languageProbability: 0.9, text: "t",
            segments: [{ startSeconds: 0, endSeconds: 1, text: "t", speakerId: "speaker_0", speakerLabel: "Speaker 1" }] },
          speakers: [{ id: "speaker_0", label: "Ana" }],
        },
      ),
    ).toMatchInlineSnapshot(`
      {
        "contentKind": null,
        "createdAt": "2026-09-22T08:41:12.345Z",
        "description": "d",
        "durationSeconds": null,
        "failure": null,
        "iconEmoji": null,
        "id": "m1",
        "keywords": [
          "k",
        ],
        "sourcePath": "users/u1/minutes/m1/source/a.pdf",
        "sourceType": "pdf",
        "speakers": [
          {
            "id": "speaker_0",
            "label": "Ana",
          },
        ],
        "status": "ready",
        "summary": {
          "icon": null,
          "sections": [
            {
              "bullets": [
                "x",
              ],
              "title": "A",
            },
          ],
          "text": "body",
          "title": "S",
        },
        "summaryLanguage": "en",
        "tagIds": [],
        "title": "Standup",
        "transcript": {
          "durationSeconds": 1,
          "languageCode": "eng",
          "languageProbability": 0.9,
          "segments": [
            {
              "endSeconds": 1,
              "speakerId": "speaker_0",
              "speakerLabel": "Speaker 1",
              "startSeconds": 0,
              "text": "t",
            },
          ],
          "text": "t",
        },
        "updatedAt": "2026-09-22T08:41:12.345Z",
      }
    `);
  });

  it("TagOutput", () => {
    expect(toTagOutput("t1", { name: "Work", nameLower: "work", minuteCount: 2, createdAt: at })).toMatchInlineSnapshot(`
      {
        "createdAt": "2026-09-22T08:41:12.345Z",
        "id": "t1",
        "minuteCount": 2,
        "name": "Work",
      }
    `);
  });

  it("UserOutput", () => {
    expect(
      toUserOutput("u1", { email: "a@b.c", displayName: "A", photoUrl: null, plan: "premium", planExpiresAt: at, minuteCount: 1, createdAt: at }, new Date("2026-09-01T00:00:00Z")),
    ).toMatchInlineSnapshot(`
      {
        "createdAt": "2026-09-22T08:41:12.345Z",
        "displayName": "A",
        "email": "a@b.c",
        "id": "u1",
        "minuteCount": 1,
        "photoUrl": null,
        "plan": "premium",
        "planExpiresAt": "2026-09-22T08:41:12.345Z",
      }
    `);
  });

  it("no output ever contains a Firestore Timestamp or undefined", () => {
    const out = toMinuteDetail("m1", { createdAt: at }, { transcript: null, speakers: [] });
    const json = JSON.stringify(out);
    expect(json).not.toMatch(/_seconds|_nanoseconds/);
    expect(JSON.parse(json)).toEqual(out); // undefined would be dropped and break equality
  });
});
