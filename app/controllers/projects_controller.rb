class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_video, only: %i[participants_progress collaborator_video_details modify_deadline close_project
                                      collaborator_manage_chapters collaborator_manage_dedicace creator_manage_chapters
                                      creator_manage_dedicace collaborator_dedicace_de_fin_post
                                      collaborator_chapters_post edit_collaborator_chapters_post
                                      creator_chapters_post creator_dedicace_de_fin_post edit_creator_chapters_post
                                      creator_refresh_video approving_collaborator_attachments invite_collaborators
                                      invite_collaborators_post]
  before_action :find_destinataire,
                only: %i[collaborator_video_details collaborator_manage_chapters creator_manage_chapters]
  before_action :define_music, only: %i[collaborator_video_details participants_progress]

  def as_creator_projects
    @creator_projects = current_user.videos
                                    .where.not(project_status: :closed)
                                    .includes(video_previews: :preview)
  end

  def as_collaborator_projects
    @collaborator_projects = Video.joins(:collaborations)
                                  .where(collaborations: { invited_user: current_user })
                                  .where.not(project_status: %i[finished closed])
                                  .includes(video_previews: :preview)
  end

  def participants_progress
    authorize @video, :participants_progress?, policy_class: ProjectPolicy
    # ContentDedicaceJob.perform_later(@video.id)
    @participants = Collaboration.where(video_id: @video.id)
                                 .includes(:invited_user, :collaborator_chapters, :collaborator_dedicace)
    @final_video_url = @video&.final_video&.attached? ? stream_video_path(@video) : nil
    @video_dedicace = VideoDedicace.find_by(video_id: @video.id)
    @video_chapters = VideoChapter.where(video: @video).order(:order)
    # Optionally, you can also filter out the inviting user if needed
    # @participants.reject! { |collab| collab.inviting_user == @video.user }
  end

  def collaborator_video_details
    authorize @video, :collaborator_video_details?, policy_class: ProjectPolicy
    collaboration = Collaboration.find_by(video: @video, invited_user: current_user)
    @collaborator_dedicace = CollaboratorDedicace.find_by(video: @video, collaboration:)
    @collaborator_chapters = CollaboratorChapter.where(video: @video, collaboration:).order(:order)
  end

  def creator_update_date
    if @video.update(end_date: params[:end_date])
      authorize @video, :creator_update_date?, policy_class: ProjectPolicy
      redirect_to project_path(@video), notice: "La date limite a été mise à jour avec succès."
    else
      flash.now[:alert] = "Une erreur est survenue. Veuillez réessayer."
      render :show
    end
  end

  def delete_collaboration
    collaboration = Collaboration.find(params[:id]) # Use the appropriate ID from the params
    video = Video.find(collaboration.video_id)
    authorize video, :delete_collaboration?, policy_class: ProjectPolicy
    if collaboration.inviting_user == current_user || collaboration.invited_user == current_user
      collaboration.destroy
      redirect_to participants_progress_path(video_id: video.id), notice: "Collaboration deleted successfully."
    else
      redirect_to participants_progress_path(video_id: video.id),
                  alert: "You are not authorized to delete this collaboration."
    end
  end

  def modify_deadline
    authorize @video, :modify_deadline?, policy_class: ProjectPolicy
    if @video.update(end_date: params[:end_date])
      redirect_to participants_progress_path(video_id: @video.id),
                  notice: "La date limite a été mise à jour avec succès."
    else
      flash.now[:alert] = "Une erreur est survenue. Veuillez réessayer."
      render :show
    end
  end

  def close_project
    authorize @video, :close_project?, policy_class: ProjectPolicy
    if @video.update!(project_status: :closed)
      redirect_to as_creator_projects_path,
                  notice: t("projects.notices.project_closed")
    else
      flash.now[:alert] = t("projects.notices.update_failed")
      render :show
    end
  end

  def collaborator_manage_chapters
    authorize @video, :collaborator_manage_chapters?, policy_class: ProjectPolicy
    define_chapter_type(CollaboratorChapter)
  end

  def collaborator_chapters_post
    authorize @video, :collaborator_chapters_post?, policy_class: ProjectPolicy
    # On authorize que certain parametre
    params_allow = params.permit(chapters: %i[select text slide_color text_family text_style text_size])["chapters"]

    chapter_to_create = [] # Un tableau a remplir de chapitre a créer
    chapter_to_updates = {} # Un hash a remplir de chapitre a modifier

    # Si le chapitre est déjà sélectionné, on doit le modifier
    find_chapters = [] # On crée un tableau servant à la requete SQL IN pour ne récupérer que des chapitres déjà crée
    params_allow.each { |k, v| find_chapters.append(k) if v["select"] == "true" }
    # On cherche avec la request SQL IN les collaborator_chapters ayant déjà un chapitre lié à l'ancien
    chapter_to_updates_model = @video.collaborator_chapters.where(chapter_type_id: find_chapters)
    chapter_to_delete = @video.collaborator_chapters.where.not(chapter_type_id: find_chapters)
    id_chapter_type = [] # L'id uniquement des chapitre_type en relation avec les chapitres video a modifier.
    chapter_to_updates_by_chapter_type = {} # Un hash permettant de faire une recherche par le chapitre_type
    chapter_to_updates_model.each do |k|
      id_chapter_type.append(k.chapter_type_id.to_s)
      chapter_to_updates_by_chapter_type[k.chapter_type_id.to_s] = k
    end
    collaboration = Collaboration.find_by(video_id: params[:video_id], invited_user: current_user)

    # On ne se prépare à créer que les éléments qu'il faut.
    params_allow.each do |k, v|
      # Si un chapitre existe déjà avec ce type de chapitre, on ne le crée pas ...
      if id_chapter_type.include?(k)
        # Si le chapitre est toujours sélectionné, on le modifie
        if v["select"] == "true"
          video_chapter = chapter_to_updates_by_chapter_type[k]
          chapter_to_updates[video_chapter.id] = {
            text: v["text"],
            slide_color: v["slide_color"],
            text_family: v["text_family"],
            text_style: v["text_style"],
            text_size: v["text_size"]
          }
        end
      elsif v["select"] == "true"
        # Si l'élément est bien séléctionné
        chapter_to_create.append({ chapter_type_id: k, text: v["text"], collaboration:,
                                   slide_color: v["slide_color"], text_family: v["text_family"],
                                   text_style: v["text_style"], text_size: v["text_size"] })
        # On l'ajoute dans la liste des éléments à supprimer
        # ... on le modifie
      end
    end

    # 12 chapitres maximum
    if (chapter_to_create.size + chapter_to_updates.size) >= 12
      flash[:alert] = "Ne sélectionnez que 12 chapitres maximum"
      return render select_chapters_path, status: :unprocessable_entity
    end

    # Création, Mise à jour et suppression
    if @video.collaborator_chapters.create(chapter_to_create) &&
       @video.collaborator_chapters.update(chapter_to_updates.keys, chapter_to_updates.values)

      @video.collaborator_chapters.each do |chapter|
        chapter.collaborator_music.destroy if chapter.collaborator_music
      end

      chapter_to_delete.destroy_all

      redirect_to collaborator_video_details_path(@video.id)
    else
      @chapterstype = ChapterType.all
      render collaborator_manage_chapters_path(@video.id), status: :unprocessable_entity
    end
  end

  def creator_chapters_post
    authorize @video, :creator_chapters_post?, policy_class: ProjectPolicy
    # On authorize que certain parametre
    params_allow = params.permit(chapters: %i[select text slide_color text_family text_style text_size])["chapters"]

    chapter_to_create = [] # Un tableau a remplir de chapitre a créer
    chapter_to_updates = {} # Un hash a remplir de chapitre a modifier

    # Si le chapitre est déjà sélectionné, on doit le modifier
    find_chapters = [] # On crée un tableau servant à la requete SQL IN pour ne récupérer que des chapitres déjà crée
    params_allow.each { |k, v| find_chapters.append(k) if v["select"] == "true" }
    # On cherche avec la request SQL IN les video_chapters ayant déjà un chapitre lié à l'ancien
    chapter_to_updates_model = @video.video_chapters.where(chapter_type_id: find_chapters)
    chapter_to_delete = @video.video_chapters.where.not(chapter_type_id: find_chapters)
    id_chapter_type = [] # L'id uniquement des chapitre_type en relation avec les chapitres video a modifier.
    chapter_to_updates_by_chapter_type = {} # Un hash permettant de faire une recherche par le chapitre_type
    chapter_to_updates_model.each do |k|
      id_chapter_type.append(k.chapter_type_id.to_s)
      chapter_to_updates_by_chapter_type[k.chapter_type_id.to_s] = k
    end

    # On ne se prépare à créer que les éléments qu'il faut.
    params_allow.each do |k, v|
      # Si un chapitre existe déjà avec ce type de chapitre, on ne le crée pas ...
      if id_chapter_type.include?(k)
        # Si le chapitre est toujours sélectionné, on le modifie
        if v["select"] == "true"
          video_chapter = chapter_to_updates_by_chapter_type[k]
          chapter_to_updates[video_chapter.id] = {
            text: v["text"],
            slide_color: v["slide_color"],
            text_family: v["text_family"],
            text_style: v["text_style"],
            text_size: v["text_size"]
          }
        end
      elsif v["select"] == "true"
        # Si l'élément est bien séléctionné
        chapter_to_create.append({ chapter_type_id: k, text: v["text"],
                                   slide_color: v["slide_color"], text_family: v["text_family"],
                                   text_style: v["text_style"], text_size: v["text_size"] })
        # On l'ajoute dans la liste des éléments à supprimer
        # ... on le modifie
      end
    end

    # 12 chapitres maximum
    if (chapter_to_create.size + chapter_to_updates.size) >= 12
      flash[:alert] = "Ne sélectionnez que 12 chapitres maximum"
      return render select_chapters_path, status: :unprocessable_entity
    end

    # Création, Mise à jour et suppression
    if @video.video_chapters.create(chapter_to_create) &&
       @video.video_chapters.update(chapter_to_updates.keys, chapter_to_updates.values)

      @video.video_chapters.each do |chapter|
        chapter.video_music.destroy if chapter.video_music
      end

      chapter_to_delete.destroy_all

      redirect_to participants_progress_path(video_id: @video.id)
    else
      @chapterstype = ChapterType.all
      render creator_manage_chapters_path(@video.id), status: :unprocessable_entity
    end
  end

  def edit_creator_chapters_post
    authorize @video, :edit_creator_chapters_post?, policy_class: ProjectPolicy
    # Update the order of chapters
    if params[:chapter_order].present?
      chapter_ids = params[:chapter_order].split(",").map(&:to_i)
      chapter_ids.each_with_index do |id, index|
        chapter = @video.video_chapters.find_by(id:)
        chapter.update(order: index + 1) if chapter
      end
    end

    # Update fields for each chapter
    params[:chapters]&.each do |chapter_id, chapter_data|
      chapter = @video.video_chapters.find_by(id: chapter_id)
      next unless chapter

      # Update text
      chapter.update(text: chapter_data[:text]) if chapter_data[:text].present?

      # Update videos order
      chapter.update(videos_order: chapter_data[:videos_order]) if chapter_data[:videos_order].present?

      # Attach new videos
      if chapter_data[:videos].present?
        chapter_data[:videos].each do |video|
          next if video.blank?

          # Skip if the file is already attached
          next if chapter.videos.any? { |v| v.filename.to_s == video.original_filename }

          if chapter.videos.count >= ChapterSharedBehavior::MEDIA_LIMIT
            flash[:alert] = I18n.t("videos.content.video_limit_alert")
            next
          end

          chapter.videos.attach(video)
        end
      end

      # Update photos order
      chapter.update(photos_order: chapter_data[:photos_order]) if chapter_data[:photos_order].present?

      # Attach new photos
      next unless chapter_data[:photos].present?

      chapter_data[:photos].each do |photo|
        next if photo.blank?

        # Skip if the file is already attached
        next if chapter.photos.any? { |p| p.filename.to_s == photo.original_filename }

        if chapter.photos.count >= ChapterSharedBehavior::MEDIA_LIMIT
          flash[:alert] = I18n.t("videos.content.photo_limit_alert")
          next
        end

        chapter.photos.attach(photo)
      end

      # # Update or create the associated video_music record
      # if chapter_data[:music_id].present?
      #   if chapter.video_music.present?
      #     chapter.video_music.update(music_id: chapter_data[:music_id])
      #   else
      #     chapter.create_video_music(music_id: chapter_data[:music_id])
      #   end
      # end
    end

    params.each do |key, value|
      # Handle music associations
      if key.start_with?("music_")
        chapter_id = key.split("_").last.to_i
        music_id = value.to_i

        # Find the corresponding video chapter
        video_chapter = @video.video_chapters.find_by(id: chapter_id)
        if video_chapter
          # Check if a predefined music exists
          music = Music.find_by(id: music_id)
          if music
            # Replace existing music association
            video_chapter.video_music&.destroy
            VideoMusic.create!(music:, video_chapter:)
          elsif video_chapter.custom_music.attached? || params["custom_music_#{video_chapter.id}"].present?
            # Skip if custom music is already attached or provided in params
            next
          else
            flash[:alert] ||= []
            flash[:alert] << "Musique non trouvée pour le chapitre #{chapter_id}."
          end
        else
          flash[:alert] ||= []
          flash[:alert] << "Chapitre non trouvé pour l'ID #{chapter_id}."
        end

      # Handle custom music uploads
      elsif key.start_with?("custom_music_")
        chapter_id = key.split("_").last.to_i
        music_file = value

        # Find the corresponding video chapter
        video_chapter = @video.video_chapters.find_by(id: chapter_id)
        if video_chapter && music_file.present?
          video_chapter.custom_music.attach(music_file)
          MusicProcessingJob.perform_later("VideoChapter", video_chapter.id)
        else
          flash[:alert] ||= []
          flash[:alert] << "Fichier de musique personnalisé manquant ou chapitre introuvable pour l'ID #{chapter_id}."
        end
      end
    end

    redirect_to participants_progress_path(video_id: @video.id), notice: "Video chapters updated successfully"
  end

  def edit_collaborator_chapters_post
    authorize @video, :edit_collaborator_chapters_post?, policy_class: ProjectPolicy

    # Update the order of chapters
    if params[:chapter_order].present?
      chapter_ids = params[:chapter_order].split(",").map(&:to_i)
      chapter_ids.each_with_index do |id, index|
        chapter = @video.collaborator_chapters.find_by(id:)
        chapter.update(order: index + 1) if chapter
      end
    end

    # Update fields for each chapter
    params[:chapters]&.each do |chapter_id, chapter_data|
      chapter = @video.collaborator_chapters.find_by(id: chapter_id)
      next unless chapter

      # Update text
      chapter.update(text: chapter_data[:text]) if chapter_data[:text].present?

      # Update videos order
      chapter.update(videos_order: chapter_data[:videos_order]) if chapter_data[:videos_order].present?

      # Attach new videos
      if chapter_data[:videos].present?
        chapter_data[:videos].each do |video|
          next if video.blank?

          # Skip if the file is already attached
          next if chapter.videos.any? { |v| v.filename.to_s == video.original_filename }

          if chapter.videos.count >= ChapterSharedBehavior::MEDIA_LIMIT
            flash[:alert] = I18n.t("videos.content.video_limit_alert")
            next
          end

          chapter.videos.attach(video)
        end
      end

      # Update photos order
      chapter.update(photos_order: chapter_data[:photos_order]) if chapter_data[:photos_order].present?

      # Attach new photos
      next unless chapter_data[:photos].present?

      chapter_data[:photos].each do |photo|
        next if photo.blank?

        # Skip if the file is already attached
        next if chapter.photos.any? { |p| p.filename.to_s == photo.original_filename }

        if chapter.photos.count >= ChapterSharedBehavior::MEDIA_LIMIT
          flash[:alert] = I18n.t("videos.content.photo_limit_alert")
          next
        end

        chapter.photos.attach(photo)
      end
    end

    params.each do |key, value|
      # Handle music associations
      if key.start_with?("music_")
        chapter_id = key.split("_").last.to_i
        music_id = value.to_i

        # Find the corresponding video chapter
        collaborator_chapter = @video.collaborator_chapters.find_by(id: chapter_id)
        if collaborator_chapter
          # Check if a predefined music exists
          music = Music.find_by(id: music_id)
          if music
            # Replace existing music association
            collaborator_chapter.collaborator_music&.destroy
            CollaboratorMusic.create!(music:, collaborator_chapter:)
          elsif collaborator_chapter.custom_music.attached? || params["custom_music_#{collaborator_chapter.id}"].present?
            # Skip if custom music is already attached or provided in params
            next
          else
            flash[:alert] ||= []
            flash[:alert] << "Musique non trouvée pour le chapitre #{chapter_id}."
          end
        else
          flash[:alert] ||= []
          flash[:alert] << "Chapitre non trouvé pour l'ID #{chapter_id}."
        end

      # Handle custom music uploads
      elsif key.start_with?("custom_music_")
        chapter_id = key.split("_").last.to_i
        music_file = value

        # Find the corresponding video chapter
        collaborator_chapter = @video.collaborator_chapters.find_by(id: chapter_id)
        if collaborator_chapter && music_file.present?
          collaborator_chapter.custom_music.attach(music_file)
          MusicProcessingJob.perform_later("CollaboratorChapter", collaborator_chapter.id)
        else
          flash[:alert] ||= []
          flash[:alert] << "Fichier de musique personnalisé manquant ou chapitre introuvable pour l'ID #{chapter_id}."
        end
      end
    end

    redirect_to collaborator_video_details_path(@video.id), notice: "Video chapters updated successfully"
  end

  def delete_collaborator_chapter
    collaborator_chapter = CollaboratorChapter.find(params[:id]) # Use the appropriate ID from the params
    authorize collaborator_chapter.video, :delete_collaborator_chapter?, policy_class: ProjectPolicy
    if collaborator_chapter.destroy!
      respond_to do |format|
        format.html do
          redirect_to collaborator_video_details_path(collaborator_chapter.video.id),
                      notice: "Chapter deleted successfully."
        end
        format.json { render json: { message: "Chapter deleted successfully" }, status: :ok }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to collaborator_video_details_path(collaborator_chapter.video.id),
                      alert: "Failed to delete the chapter."
        end
        format.json { render json: { error: "Failed to delete the chapter" }, status: :unprocessable_entity }
      end
    end
  end

  def delete_creator_chapter
    video_chapter = VideoChapter.find(params[:id]) # Use the appropriate ID from the params
    authorize video_chapter.video, :delete_creator_chapter?, policy_class: ProjectPolicy
    if video_chapter.destroy!
      respond_to do |format|
        format.html do
          redirect_to participants_progress_path(video_id: @video.id), notice: "Chapter deleted successfully."
        end
        format.json { render json: { message: "Chapter deleted successfully" }, status: :ok }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to participants_progress_path(video_id: @video.id), alert: "Failed to delete the chapter."
        end
        format.json { render json: { error: "Failed to delete the chapter" }, status: :unprocessable_entity }
      end
    end
  end

  def collaborator_manage_dedicace
    authorize @video, :collaborator_manage_dedicace?, policy_class: ProjectPolicy
    @dedicaces = Dedicace.all
    @dedicace = @video.dedicace
    collaboration = Collaboration.find_by(video_id: @video.id, invited_user: current_user)
    @collaborator_dedicace = CollaboratorDedicace.find_by(video_id: @video.id, collaboration:)
  end

  def collaborator_dedicace_de_fin_post
    authorize @video, :collaborator_dedicace_de_fin_post?, policy_class: ProjectPolicy

    collaboration = Collaboration.find_by(video_id: params[:video_id], invited_user: current_user)
    unless collaboration
      flash[:alert] = "Collaboration not found"
      return redirect_to collaborator_manage_dedicace_path(@video.id)
    end

    collaborator_dedicace = CollaboratorDedicace.find_or_initialize_by(
      video_id: @video.id,
      collaboration:
    )
    collaborator_dedicace.dedicace_id = params[:collaborator_dedicace]

    if params[:creator_end_dedication_video].present?
      collaborator_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video])
    elsif params[:creator_end_dedication_video_uploaded].present?
      collaborator_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video_uploaded])
    end

    if collaborator_dedicace.save
      VideoProcessingJob.perform_later(collaborator_dedicace.id, "CollaboratorDedicace")
      flash[:notice] = I18n.t("projects.dedicace_saved")
    else
      flash[:alert] = I18n.t("projects.dedicace_save_failed", errors: collaborator_dedicace.errors.full_messages.to_sentence)
    end

    redirect_to collaborator_manage_dedicace_path(@video.id)
  end

  def creator_dedicace_de_fin_post
    authorize @video, :creator_dedicace_de_fin_post?, policy_class: ProjectPolicy

    video_dedicace = VideoDedicace.find_or_initialize_by(
      video_id: @video.id
    )

    video_dedicace.dedicace_id = params[:video_dedicace]

    if params[:creator_end_dedication_video].present?
      video_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video])
    elsif params[:creator_end_dedication_video_uploaded].present?
      video_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video_uploaded])
    end

    if video_dedicace.save
      VideoProcessingJob.perform_later(video_dedicace.id, "VideoDedicace")
      flash[:notice] = I18n.t("projects.dedicace_saved")
    else
      flash[:alert] = I18n.t("projects.dedicace_save_failed", errors: video_dedicace.errors.full_messages.to_sentence)
    end

    redirect_to participants_progress_path(video_id: @video.id)
  end

  def creator_manage_chapters
    authorize @video, :creator_manage_chapters?, policy_class: ProjectPolicy
    define_chapter_type(VideoChapter)
  end

  def creator_manage_dedicace
    authorize @video, :creator_manage_dedicace?, policy_class: ProjectPolicy
    @dedicaces = Dedicace.all
    @dedicace = @video.dedicace
    unless @dedicace
      redirect_to participants_progress_path(video_id: @video.id), alert: I18n.t("projects.creator_manage_dedicace.dedicace_missing")
      return
    end

    @video_dedicace = @video.video_dedicace || @video.create_video_dedicace!(dedicace: @dedicace)
  end

  def creator_refresh_video
    authorize @video, :creator_refresh_video?, policy_class: ProjectPolicy
    # Update the status to processing
    @video.update!(concat_status: :processing, processing_progress: 0)

    # Purge existing final video attachments
    @video.final_video.purge if @video.final_video.attached?
    @video.final_video_xml.purge if @video.final_video_xml.attached?

    # Enqueue the job to process the video again
    ContentDedicaceJob.perform_later(@video.id)
    flash[:notice] = I18n.t("videos.messages.processing_restarted")

    # Redirect to the same action without the refresh parameter
    redirect_to participants_progress_path(video_id: @video.id) and return
  end

  def approving_collaborator_attachments
    authorize @video, :approving_collaborator_attachments?, policy_class: ProjectPolicy

    # Extract the parameters
    collaborator_attachment = params[:collaborator_attachment]
    collaboration_id = collaborator_attachment[:collaboration_id]

    # Update CollaboratorDedicace
    if collaborator_attachment[:dedicace].present?
      dedicace = CollaboratorDedicace.find_by(collaboration_id:)
      if dedicace
        dedicace.update(approved_by_creator: ActiveModel::Type::Boolean.new.cast(collaborator_attachment[:dedicace]))
      end
    end

    # Update CollaboratorChapters
    if collaborator_attachment[:chapter].present?
      collaborator_attachment[:chapter].each do |chapter_id, approved|
        chapter = CollaboratorChapter.find_by(id: chapter_id, collaboration_id:)
        chapter.update(approved_by_creator: ActiveModel::Type::Boolean.new.cast(approved)) if chapter
      end
    end

    redirect_to participants_progress_path(video_id: @video.id), notice: "Approvals have been updated successfully."
  end

  def invite_collaborators
    authorize @video, :invite_collaborators?, policy_class: ProjectPolicy

  end

  def invite_collaborators_post
    authorize @video, :invite_collaborators_post?, policy_class: ProjectPolicy
    # Le mailer fonctionne mais pas le join
    email = params[:email]
    if email.blank?
      flash[:alert] = I18n.t("videos.share.email_required")
      return render invite_collaborators_path(video_id: @video.id), status: :unprocessable_entity
    end

    # create Collab obj
    collab_user = User.find_by_email(params[:email])
    if collab_user == @video.user
      flash[:alert] = I18n.t("videos.share.owner_email")
      return render invite_collaborators_path(video_id: @video.id), status: :unprocessable_entity
    end

    @video.update(video_type: :colab) # update to collab if was solo before
    collaboration = Collaboration.create!(
      video: @video,
      inviting_user: current_user,
      invited_email: params[:email],
      invited_user: collab_user # may be nil if user doesn't exist yet
    )

    InvitationMailer.with(url: join_url(@video.token), email:, locale: I18n.locale).send_invitation.deliver_later
    flash[:notice] = I18n.t("videos.share.invitation_sent")
    redirect_to invite_collaborators_path(video_id: @video.id)
  end

  private

  def define_chapter_type(model)
    table_name = model.to_s.underscore.pluralize
    query = <<-SQL
      SELECT DISTINCT "chapter_types".id, "chapter_types".created_at, "#{table_name}".text,
                      "#{table_name}".slide_color, "#{table_name}".text_family,
                      "#{table_name}".text_style, "#{table_name}".text_size
      FROM "chapter_types"
      LEFT OUTER JOIN "#{table_name}"
        ON "#{table_name}"."chapter_type_id" = "chapter_types"."id"
        AND "#{table_name}".video_id = $1
      ORDER BY "chapter_types".created_at ASC
    SQL

    q_results = ActiveRecord::Base.connection.exec_query(query, "selectChapterWithData", [@video.id])

    r_only_id = q_results.rows.map { |v| v[0] }
    chapter_types = ChapterType.where(id: r_only_id)
    chapter_types_h = chapter_types.index_by(&:id)

    @chapterstype = q_results.as_json.map do |k|
      {
        ct: chapter_types_h[k["id"]],
        text: k["text"],
        slide_color: k["slide_color"],
        text_family: k["text_family"],
        text_style: k["text_style"],
        text_size: k["text_size"],
        select: k["text"].present?
      }
    end
  end

  def find_video
    @video = Video.find((params[:video_id].presence || params[:id]))
  end

  def find_destinataire
    @destinataires = @video.video_destinataires
  end

  def define_music
    @musics = Music.with_attached_music.map do |music|
      {
        id: music.id,
        name: music.name,
        waveform: music.waveform.to_json,
        url: music.music.attached? ? url_for(music.music) : nil
      }
    end
    # @musics = Music.all
  end
end
