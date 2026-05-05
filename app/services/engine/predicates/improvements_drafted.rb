module Engine
  module Predicates
    class ImprovementsDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "improvement_drafts").detect do |item|
          Array(item.data["improvements"]).any? do |improvement|
            Array(improvement["files"]).any? { |file| file["path"].present? && file["content"].present? }
          end
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing improvement_drafts artifact with file content")
      end
    end
  end
end
