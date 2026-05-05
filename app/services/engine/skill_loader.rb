module Engine
  class SkillLoader
    SKILLS_DIR = Rails.root.join("skills")

    VALID_SKILL_NAME = /\A[a-z0-9_-]+\z/

    def self.load(name)
      return nil unless name.to_s.match?(VALID_SKILL_NAME)

      path = SKILLS_DIR.join("#{name}.md")
      return nil unless path.exist?

      path.read
    end

    def self.load_all(names)
      names.each_with_object({}) do |name, result|
        content = load(name)
        result[name] = content if content
      end
    end
  end
end
