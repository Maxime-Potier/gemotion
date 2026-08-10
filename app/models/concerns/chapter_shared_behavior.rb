module ChapterSharedBehavior
  extend ActiveSupport::Concern

  MEDIA_LIMIT = 20

  included do
    belongs_to :chapter_type
    belongs_to :video
    # has_one_attached :element
    has_many_attached :videos, dependent: :destroy
    has_many_attached :photos, dependent: :destroy
    # validates :order, numericality: { only_integer: true }

    validates :text, presence: true
    validate :media_attachment_counts_within_limit
  end

  def ordered_videos
    video_filenames = (videos_order || '').split(',').map(&:strip)
    videos.sort_by { |v| video_filenames.index(v.filename.to_s) || videos.size }
  end

  def ordered_photos
    photo_filenames = (photos_order || '').split(',').map(&:strip)
    photos.sort_by { |p| photo_filenames.index(p.filename.to_s) || photos.size }
  end

  private

  def media_attachment_counts_within_limit
    errors.add(:videos, "cannot exceed #{MEDIA_LIMIT} files") if videos.attachments.size > MEDIA_LIMIT
    errors.add(:photos, "cannot exceed #{MEDIA_LIMIT} files") if photos.attachments.size > MEDIA_LIMIT
  end

  # def videos_order_list
  #   videos_order.split(',')
  # end

  # def photos_order_list
  #   photos_order.split(',')
  # end


end
