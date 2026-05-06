class WideReportSearch
  def call(account_id:)
    WideReport.select("*").where(account_id: account_id).map do |report|
      { id: report.id, title: report.title }
    end
  end
end
