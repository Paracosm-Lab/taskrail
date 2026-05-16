require "rails_helper"

RSpec.describe Adapters::ResponseParser do
  describe ".extract_structured_fields" do
    it "extracts spawn_work_items from a JSON block in the response" do
      response = <<~TEXT
        I analyzed the clusters and found thin instrumentation.

        ```json
        {
          "spawn_work_items": [
            {
              "queue_slug": "development",
              "title": "Improve billing-service instrumentation",
              "spec_inline": "Add Sentry.set_context calls",
              "tags": { "domain": "instrumentation" }
            }
          ]
        }
        ```

        That concludes my assessment.
      TEXT

      fields = described_class.extract_structured_fields(response)

      expect(fields).to have_key("spawn_work_items")
      expect(fields["spawn_work_items"].length).to eq(1)
      expect(fields["spawn_work_items"].first["title"]).to eq("Improve billing-service instrumentation")
    end

    it "extracts tags from a JSON block" do
      response = <<~TEXT
        ```json
        {
          "tags": { "cost": "low", "risk": "high" }
        }
        ```
      TEXT

      fields = described_class.extract_structured_fields(response)

      expect(fields["tags"]).to eq("cost" => "low", "risk" => "high")
    end

    it "merges fields from multiple JSON blocks" do
      response = <<~TEXT
        First block:
        ```json
        { "tags": { "cost": "low" } }
        ```

        Second block:
        ```json
        { "spawn_work_items": [{ "queue_slug": "dev", "title": "Fix it" }] }
        ```
      TEXT

      fields = described_class.extract_structured_fields(response)

      expect(fields).to have_key("tags")
      expect(fields).to have_key("spawn_work_items")
    end

    it "returns empty hash when response has no JSON blocks" do
      fields = described_class.extract_structured_fields("Just plain text, no JSON here.")
      expect(fields).to eq({})
    end

    it "skips malformed JSON blocks" do
      response = <<~TEXT
        ```json
        { this is not valid json }
        ```

        ```json
        { "tags": { "valid": "yes" } }
        ```
      TEXT

      fields = described_class.extract_structured_fields(response)

      expect(fields["tags"]).to eq("valid" => "yes")
    end

    it "handles JSON blocks without the json language tag" do
      response = <<~TEXT
        ```
        { "tags": { "cost": "medium" } }
        ```
      TEXT

      fields = described_class.extract_structured_fields(response)

      expect(fields["tags"]).to eq("cost" => "medium")
    end

    it "only extracts known structured keys" do
      response = <<~TEXT
        ```json
        {
          "spawn_work_items": [],
          "tags": {},
          "random_field": "should be ignored",
          "assessments": [{"cluster_id": "c1"}]
        }
        ```
      TEXT

      fields = described_class.extract_structured_fields(response)

      expect(fields).to have_key("spawn_work_items")
      expect(fields).to have_key("tags")
      expect(fields).not_to have_key("random_field")
      expect(fields).not_to have_key("assessments")
    end

    it "extracts development workflow fields from a plain JSON response" do
      response = <<~JSON
        {
          "children": [
            { "title": "Build calendar export", "spec_inline": "Add DTSTART and SUMMARY", "tags": { "slice": "calendar" } }
          ],
          "verdict": "approved",
          "feedback": "ship it",
          "artifacts": [
            { "kind": "branch", "data": { "name": "taskrail/calendar-export" } }
          ]
        }
      JSON

      fields = described_class.extract_structured_fields(response)

      expect(fields["children"].first["title"]).to eq("Build calendar export")
      expect(fields["verdict"]).to eq("approved")
      expect(fields["feedback"]).to eq("ship it")
      expect(fields["artifacts"].first).to eq("kind" => "branch", "data" => { "name" => "taskrail/calendar-export" })
    end

    it "extracts structured fields from Claude JSON output wrappers" do
      response = JSON.dump(
        "type" => "result",
        "result" => <<~TEXT
          ```json
          { "verdict": "approved" }
          ```
        TEXT
      )

      fields = described_class.extract_structured_fields(response)

      expect(fields["verdict"]).to eq("approved")
    end
  end
end
