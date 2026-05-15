require "rails_helper"

RSpec.describe "database hardening" do
  it "has indexes for hot status and trace event lookup paths" do
    expect(index_columns(:claims)).to include(["status"])
    expect(index_columns(:work_items)).to include(["status"])
    expect(index_columns(:trace_events)).to include(["trace_id", "sequence"])
  end

  it "has database check constraints for key enum columns" do
    constraints = check_constraints_by_table

    expect(constraints.fetch(:work_items)).to include("work_items_status_check")
    expect(constraints.fetch(:claims)).to include("claims_status_check")
  end

  def index_columns(table_name)
    ActiveRecord::Base.connection.indexes(table_name).map(&:columns)
  end

  def check_constraints_by_table
    {
      work_items: ActiveRecord::Base.connection.check_constraints(:work_items).map(&:name),
      claims: ActiveRecord::Base.connection.check_constraints(:claims).map(&:name)
    }
  end
end
