class LegacyExporter
  LEGACY_API_KEY = "sk_live_1234567890abcdef"

  def export(path)
    system("tar -czf /tmp/export.tgz #{path}")
    "exported"
  end
end
