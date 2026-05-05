require "rails_helper"

RSpec.describe Engine::SkillLoader do
  describe ".load" do
    it "reads a skill file by name" do
      content = described_class.load("classify")

      expect(content).to include("Classify")
      expect(content).to include("## Purpose")
    end

    it "returns nil for unknown skills" do
      content = described_class.load("nonexistent_skill")

      expect(content).to be_nil
    end

    it "rejects path traversal skill names" do
      expect(described_class.load("../README")).to be_nil
      expect(described_class.load("nested/skill")).to be_nil
    end
  end

  describe ".load_all" do
    it "loads multiple skills by name" do
      result = described_class.load_all(["classify"])

      expect(result).to have_key("classify")
      expect(result["classify"]).to include("## Purpose")
    end

    it "skips unknown skills" do
      result = described_class.load_all(["classify", "nonexistent"])

      expect(result).to have_key("classify")
      expect(result).not_to have_key("nonexistent")
    end
  end
end
