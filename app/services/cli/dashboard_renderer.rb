module Cli
  class DashboardRenderer
    TITLE_LIMIT = 48

    def initialize(data:, color: false)
      @data = data
      @color = color
    end

    def render
      [
        header,
        stages_section,
        work_items_section,
        costs_section
      ].join("\n")
    end

    private

    attr_reader :data

    def header
      queue_name = cell(data.queue.fetch("name", data.queue_slug))
      <<~TEXT.chomp
        StupidClaw Dashboard
        API: #{cell(data.api_url)}
        Queue: #{queue_name} (#{cell(data.queue_slug)})
      TEXT
    end

    def stages_section
      rows = data.stages.map do |stage|
        format("%-12s %-16s %s", cell(stage.fetch("name", "")), cell(stage.fetch("adapter_type", "")), Array(stage.fetch("completion_criteria", [])).map { |criterion| cell(criterion) }.join(", "))
      end

      (["Stages"] + rows).join("\n")
    end

    def work_items_section
      rows = data.work_items.map do |item|
        format("%-4s %-10s %-10s %s", cell(item.fetch("id", "")), cell(item.fetch("status", "")), cell(item.fetch("stage_name", "")), work_item_detail(item))
      end
      rows = ["No work items."] if rows.empty?

      (["Work Items", "ID   Status     Stage      Title"] + rows).join("\n")
    end

    def costs_section
      <<~TEXT.chomp
        Costs
        Total cost: #{number(data.costs.fetch("total_cost_cents", 0))} cents
        Tokens in/out: #{number(data.costs.fetch("total_tokens_in", 0))} / #{number(data.costs.fetch("total_tokens_out", 0))}
      TEXT
    end

    def truncate(value)
      text = value.to_s
      return text if text.length <= TITLE_LIMIT

      "#{text[0, TITLE_LIMIT - 1]}…"
    end

    def work_item_detail(item)
      parts = [truncate(cell(item.fetch("title", "")))]
      parts << active_claim_text(item["active_claim"]) if item["active_claim"]
      parts << escalation_text(item["escalation"]) if item["escalation"]
      parts.reject(&:empty?).join(" ")
    end

    def active_claim_text(claim)
      parts = ["#{cell(claim.fetch("agent_type", ""))}:#{cell(claim.fetch("status", ""))}"]
      parts << "async" if claim["async_execution"]
      parts << cell(claim.fetch("external_id", ""))
      parts.reject(&:empty?).join(" ")
    end

    def escalation_text(escalation)
      return "" unless escalation["human_action_required"]

      message = escalation["question"] || escalation["reason"] || "action required"
      "HUMAN: #{truncate(cell(message))}"
    end

    def cell(value)
      value.to_s
        .gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, "")
        .gsub(/[[:cntrl:]]+/, " ")
        .squeeze(" ")
        .strip
    end

    def number(value)
      return 0 if value.nil?
      return 0 if value.respond_to?(:empty?) && value.empty?

      value
    end
  end
end
