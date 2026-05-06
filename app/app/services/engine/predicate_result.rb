module Engine
  class PredicateResult
    attr_reader :reason, :evidence

    def self.pass(evidence: {})
      new(passed: true, evidence: evidence)
    end

    def self.fail(reason:, evidence: {})
      new(passed: false, reason: reason, evidence: evidence)
    end

    def initialize(passed:, reason: nil, evidence: {})
      @passed = passed
      @reason = reason
      @evidence = evidence
    end

    def passed?
      @passed
    end
  end
end
