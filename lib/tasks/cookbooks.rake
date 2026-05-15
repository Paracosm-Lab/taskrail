namespace :cookbooks do
  desc "Run a cookbook against TaskRail itself using real Claude. Usage: rake cookbooks:run[security_scan]"
  task :run, [:cookbook] => :environment do |_t, args|
    cookbook = args[:cookbook]
    abort "Usage: rake cookbooks:run[cookbook_name]" if cookbook.blank?

    queue = WorkQueue.find_by(slug: cookbook)
    abort "Queue not found: #{cookbook}. Run db:seed first." unless queue

    puts "Creating work item in queue: #{queue.slug} (#{queue.stages.count} stages)"
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "#{queue.name} — rake run #{Time.current.strftime('%Y-%m-%d %H:%M')}",
      spec_url: "rake://cookbooks/run/#{cookbook}",
      stage_name: queue.stages.first
    )
    puts "Work item #{work_item.id} created at stage: #{work_item.stage_name}"

    loop do
      Engine::Runner.new.call
      work_item.reload

      case work_item.status
      when "completed"
        puts "Done. Work item completed at stage: #{work_item.stage_name}"
        puts "Artifacts: #{work_item.artifacts.pluck(:kind).join(', ')}"
        break
      when "cancelled"
        puts "Work item was cancelled."
        break
      when "blocked"
        puts "Work item is blocked at stage: #{work_item.stage_name}"
        puts "Check claims for details."
        break
      else
        puts "Stage: #{work_item.stage_name} (#{work_item.status})"
        sleep 2
      end
    end
  end

  desc "List all available cookbooks (seeded queues)"
  task list: :environment do
    WorkQueue.order(:slug).each do |q|
      puts "#{q.slug.ljust(30)} #{q.stages.count} stages"
    end
  end
end
