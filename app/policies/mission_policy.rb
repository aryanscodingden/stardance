class MissionPolicy < ApplicationPolicy
  def index? = true

  # Show page renders for all non-soft-deleted missions, even if windowed
  # outside the start/end range or disabled — historical and "coming soon"
  # links shouldn't 404. Soft-deleted missions remain hidden because the
  # default scope excludes them; this policy never sees them.
  def show? = true
  def gallery? = true
  def guide? = true

  def manage?
    return false unless user.present?
    # Admins and global mission reviewers manage every mission, live or not.
    return true if mission_admin?
    # Owners can manage live missions only; once admin soft-deletes a mission,
    # ownership goes dormant until an admin restores it.
    return false if record.deleted_at?
    record.memberships.exists?(user_id: user.id, role: :owner)
  end

  # Can open this mission's submission review queue. Mirrors
  # Admin::Missions::SubmissionsController (global_reviewer? + accessible_mission?):
  # admins, helpers, and global mission reviewers see every mission's queue;
  # everyone else needs a membership on this mission — owner OR reviewer role.
  def review_queue?
    return false unless user.present?
    return true if user.admin? || user.has_role?(:helper) || user.has_role?(:mission_reviewer)
    record.memberships.exists?(user_id: user.id)
  end

  # Admin-only sections of the merged /admin/missions/:slug/edit page:
  # slug rename, owner add/remove, and the danger zone (soft-delete / restore).
  # Non-admin owners can manage everything else, but ownership and the public
  # URL stay a mission-admin prerogative.
  def manage_owners? = mission_admin?

  def destroy? = mission_admin?

  private

  # Full mission-management rights: site admins and the global mission_reviewer
  # role, which grants admin-equivalent control over every mission without
  # making the user a site-wide admin.
  def mission_admin? = user&.admin? || user&.mission_reviewer?
end
