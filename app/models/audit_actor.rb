module AuditActor
  def self.current
    User.find_by(id: PaperTrail.request.whodunnit)
  end
end
