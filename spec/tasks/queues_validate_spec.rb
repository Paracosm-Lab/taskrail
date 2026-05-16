require "spec_helper"
require "yaml"
require "tmpdir"
require "fileutils"
require_relative "../../lib/queue_config_validator"

RSpec.describe QueueConfigValidator do
  let(:valid_config) do
    {
      "name" => "My Queue",
      "slug" => "my-queue",
      "stages" => ["intake", "build", "done"],
      "stage_configs" => {
        "intake" => { "adapter_type" => "fake" },
        "build"  => { "adapter_type" => "claude" },
        "done"   => { "adapter_type" => "noop" }
      }
    }
  end

  describe ".validate" do
    context "with a valid config" do
      it "returns no errors" do
        errors = described_class.validate(valid_config, label: "test.yml")
        expect(errors).to be_empty
      end
    end

    context "when 'name' is missing" do
      it "returns an error mentioning the missing key" do
        config = valid_config.except("name")
        errors = described_class.validate(config, label: "missing_name.yml")
        expect(errors).to include(a_string_matching(/missing required keys.*name/i))
      end
    end

    context "when 'slug' is missing" do
      it "returns an error mentioning the missing key" do
        config = valid_config.except("slug")
        errors = described_class.validate(config, label: "missing_slug.yml")
        expect(errors).to include(a_string_matching(/missing required keys.*slug/i))
      end
    end

    context "when multiple required keys are missing" do
      it "reports both missing keys somewhere in the error output" do
        config = valid_config.except("name", "stages")
        errors = described_class.validate(config, label: "missing_multi.yml")
        combined = errors.join(" ")
        aggregate_failures do
          expect(combined).to match(/name/)
          expect(combined).to match(/stages/)
        end
      end
    end

    context "when a stage_config key is not listed in 'stages'" do
      it "returns an error identifying the offending key" do
        config = valid_config.merge(
          "stage_configs" => valid_config["stage_configs"].merge(
            "nonexistent_stage" => { "adapter_type" => "fake" }
          )
        )
        errors = described_class.validate(config, label: "bad_stage_key.yml")
        expect(errors).to include(a_string_matching(/nonexistent_stage.*not listed in 'stages'/i))
      end
    end

    context "when a stage_config entry is missing 'adapter_type'" do
      it "returns an error identifying the stage and the missing field" do
        config = valid_config.dup
        config["stage_configs"] = {
          "intake" => { "adapter_type" => "fake" },
          "build"  => { "other_key" => "value" },
          "done"   => { "adapter_type" => "noop" }
        }
        errors = described_class.validate(config, label: "no_adapter.yml")
        expect(errors).to include(a_string_matching(/build.*adapter_type/i))
      end
    end

    context "when a stage_config 'adapter_type' is blank" do
      it "returns an error for the blank adapter_type" do
        config = valid_config.dup
        config["stage_configs"] = {
          "intake" => { "adapter_type" => "   " },
          "build"  => { "adapter_type" => "claude" },
          "done"   => { "adapter_type" => "noop" }
        }
        errors = described_class.validate(config, label: "blank_adapter.yml")
        expect(errors).to include(a_string_matching(/intake.*adapter_type/i))
      end
    end

    context "when 'stages' is empty" do
      it "returns an error about stages" do
        config = valid_config.merge("stages" => [])
        errors = described_class.validate(config, label: "empty_stages.yml")
        expect(errors).to include(a_string_matching(/stages.*non-empty/i))
      end
    end

    context "when 'stages' is not an array" do
      it "returns an error about stages" do
        config = valid_config.merge("stages" => "intake,build")
        errors = described_class.validate(config, label: "bad_stages.yml")
        expect(errors).to include(a_string_matching(/stages.*non-empty Array/i))
      end
    end

    context "when 'stage_configs' is not a Hash" do
      it "returns an error about stage_configs" do
        config = valid_config.merge("stage_configs" => ["intake"])
        errors = described_class.validate(config, label: "bad_stage_configs.yml")
        expect(errors).to include(a_string_matching(/stage_configs.*Hash/i))
      end
    end

    context "when the config is not a Hash at all" do
      it "returns an error" do
        errors = described_class.validate("just a string", label: "not_a_hash.yml")
        expect(errors).to include(a_string_matching(/did not parse to a Hash/i))
      end
    end
  end

  describe ".validate_dir" do
    let(:tmpdir) { Dir.mktmpdir("queue_validate_spec") }

    after { FileUtils.remove_entry(tmpdir) }

    def write_yaml(filename, content)
      File.write(File.join(tmpdir, filename), content.to_yaml)
    end

    it "returns an empty hash when all files are valid" do
      write_yaml("good.yml", valid_config)
      result = described_class.validate_dir(tmpdir)
      expect(result).to be_empty
    end

    it "returns errors keyed by file path for invalid files" do
      bad_config = valid_config.except("name")
      write_yaml("bad.yml", bad_config)
      result = described_class.validate_dir(tmpdir)
      expect(result.keys.map { |p| File.basename(p) }).to include("bad.yml")
    end

    it "records a parse error for malformed YAML" do
      File.write(File.join(tmpdir, "broken.yml"), "key: [\nunclosed")
      result = described_class.validate_dir(tmpdir)
      path = result.keys.find { |p| p.end_with?("broken.yml") }
      expect(path).not_to be_nil
      expect(result[path].first).to match(/YAML parse error/i)
    end
  end
end
