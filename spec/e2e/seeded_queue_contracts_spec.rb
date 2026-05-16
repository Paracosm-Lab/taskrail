require "rails_helper"

RSpec.describe "seeded queue contracts" do
  before do
    load Rails.root.join("db/seeds.rb")
    StageConfig.update_all(adapter_type: "fake")
  end

  WorkQueueConfig = Struct.new(:slug, :max_ticks, keyword_init: true)

  queue_configs = Rails.root.glob("config/queues/*.yml").sort.map do |path|
    config = YAML.load_file(path)
    WorkQueueConfig.new(slug: config.fetch("slug"), max_ticks: config.fetch("stages").length * 20)
  end

  queue_configs.each do |queue_config|
    it "processes the #{queue_config.slug} queue through its seeded stages" do
      queue = WorkQueue.find_by!(slug: queue_config.slug)
      work_item = WorkItem.create!(
        work_queue: queue,
        title: "E2E #{queue.slug}",
        spec_url: "opaque://#{queue.slug}",
        stage_name: queue.stages.first
      )

      queue_config.max_ticks.times do
        Engine::Runner.new.call
        break if work_item.reload.completed? || work_item.blocked?
      end

      expect(work_item).to be_completed, failure_summary(work_item)
      expect(work_item.stage_name).to eq("done")
      expect(work_item.claims.completed.count).to be >= queue.stages.length - 1
      expect(work_item.transition_logs.pluck(:trigger)).to include("rule_satisfied")
    end
  end

  def failure_summary(work_item)
    logs = work_item.transition_logs.order(:created_at).map do |log|
      "#{log.from_stage}->#{log.to_stage}: #{log.trigger} #{log.details}"
    end
    claims = work_item.claims.order(:created_at).map do |claim|
      "#{claim.agent_type}/#{claim.status}: #{claim.metadata}"
    end

    <<~SUMMARY
      expected #{work_item.work_queue.slug} to complete, got status=#{work_item.status} stage=#{work_item.stage_name}
      transition logs:
      #{logs.join("\n")}
      claims:
      #{claims.join("\n")}
    SUMMARY
  end
end
