class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_video, only: %i[participants_progress collaborator_video_details modify_deadline close_project
                                      collaborator_manage_chapters collaborator_manage_dedicace creator_manage_chapters
                                      creator_manage_dedicace collaborator_dedicace_de_fin_post
                                      collaborator_chapters_post edit_collaborator_chapters_post
                                      creator_chapters_post creator_dedicace_de_fin_post edit_creator_chapters_post
                                      creator_refresh_video approving_collaborator_attachments]
  before_action :find_destinataire, only: %i[collaborator_video_details collaborator_manage_dedicace]
  def as_creator_projects
    @creator_projects = current_user.videos.left_joins(:video_previews)
                                            .where.not(project_status: [:finished, :closed])
                                            .where("video_previews.order = 1 OR video_previews.order IS NULL")
                                            .select("videos.*, COALESCE(video_previews.id, NULL) AS video_preview_id, COALESCE(video_previews.preview_id, NULL) AS preview_id")
  end

  def as_collaborator_projects
    @collaborator_projects = Video.joins(:collaborations)
                                  .left_joins(:video_previews)
                                  .where(collaborations: { invited_user: current_user })
                                  .where.not(project_status: [:finished, :closed])
                                  .where(video_previews: { order: 1 })
                                  .select("videos.*, video_previews.id AS video_preview_id, video_previews.preview_id AS preview_id")
  end

  def participants_progress
    authorize @video, :participants_progress?, policy_class: ProjectPolicy
    @participants = Collaboration.where(video_id: @video.id)
                                 .includes(:invited_user, :collaborator_chapters, :collaborator_dedicace)
    @final_video_url = @video&.final_video&.attached? ? url_for(@video.final_video) : nil
    @video_dedicace = VideoDedicace.find_by(video_id: @video.id)
    @video_chapters = VideoChapter.where(video: @video).order(:order)
    @musics = Music.all
    # Optionally, you can also filter out the inviting user if needed
    # @participants.reject! { |collab| collab.inviting_user == @video.user }
  end

  def collaborator_video_details
    authorize @video, :collaborator_video_details?, policy_class: ProjectPolicy
    collaboration = Collaboration.find_by(video: @video, invited_user: current_user)
    @collaborator_dedicace = CollaboratorDedicace.find_by(video: @video, collaboration: collaboration)
    @collaborator_chapters = CollaboratorChapter.where(video: @video, collaboration: collaboration).order(:order)
    @musics = Music.all
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
      redirect_to participants_progress_path(video_id: video.id), notice: 'Collaboration deleted successfully.'
    else
      redirect_to participants_progress_path(video_id: video.id), alert: 'You are not authorized to delete this collaboration.'
    end
  end

  def modify_deadline
    authorize @video, :modify_deadline?, policy_class: ProjectPolicy
    if @video.update(end_date: params[:end_date])
      redirect_to participants_progress_path(video_id: @video.id), notice: "La date limite a été mise à jour avec succès."
    else
      flash.now[:alert] = "Une erreur est survenue. Veuillez réessayer."
      render :show
    end
  end

  def close_project
    authorize @video, :close_project?, policy_class: ProjectPolicy
    if @video.update!(project_status: :closed)
      redirect_to as_creator_projects_path, notice: "Vous avez clôturé votre projet. Mais nous serons toujours ravis de vous revoir !"
    else
      flash.now[:alert] = "Une erreur est survenue. Veuillez réessayer."
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
        chapter_to_create.append({ chapter_type_id: k, text: v["text"], collaboration: collaboration,
                                   slide_color: v["slide_color"], text_family: v["text_family"],
                                   text_style: v["text_style"], text_size: v["text_size"]})
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
                                   text_style: v["text_style"], text_size: v["text_size"]})
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
      chapter_ids = params[:chapter_order].split(',').map(&:to_i)
      chapter_ids.each_with_index do |id, index|
        chapter = @video.video_chapters.find_by(id: id)
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

          # Purge the oldest video if there are already 2 videos
          chapter.videos.first.purge if chapter.videos.count >= 2

          chapter.videos.attach(video)
        end
      end

      # Update photos order
      chapter.update(photos_order: chapter_data[:photos_order]) if chapter_data[:photos_order].present?

      # Attach new photos
      if chapter_data[:photos].present?
        chapter_data[:photos].each do |photo|
          next if photo.blank?

          # Skip if the file is already attached
          next if chapter.photos.any? { |p| p.filename.to_s == photo.original_filename }

          # Purge the oldest photo if there are already 2 photos
          chapter.photos.first.purge if chapter.photos.count >= 2

          chapter.photos.attach(photo)
        end
      end

      # Update or create the associated video_music record
      if chapter_data[:music_id].present?
        if chapter.video_music.present?
          chapter.video_music.update(music_id: chapter_data[:music_id])
        else
          chapter.create_video_music(music_id: chapter_data[:music_id])
        end
      end
    end

    redirect_to participants_progress_path(video_id: @video.id), notice: 'Video chapters updated successfully'
  end

  def edit_collaborator_chapters_post
    authorize @video, :edit_collaborator_chapters_post?, policy_class: ProjectPolicy

    # Update the order of chapters
    if params[:chapter_order].present?
      chapter_ids = params[:chapter_order].split(',').map(&:to_i)
      chapter_ids.each_with_index do |id, index|
        chapter = @video.collaborator_chapters.find_by(id: id)
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

          # Purge the oldest video if there are already 2 videos
          chapter.videos.first.purge if chapter.videos.count >= 2

          chapter.videos.attach(video)
        end
      end

      # Update photos order
      chapter.update(photos_order: chapter_data[:photos_order]) if chapter_data[:photos_order].present?

      # Attach new photos
      if chapter_data[:photos].present?
        chapter_data[:photos].each do |photo|
          next if photo.blank?

          # Skip if the file is already attached
          next if chapter.photos.any? { |p| p.filename.to_s == photo.original_filename }

          # Purge the oldest photo if there are already 2 photos
          chapter.photos.first.purge if chapter.photos.count >= 2

          chapter.photos.attach(photo)
        end
      end

      # Update or create the associated video_music record
      if chapter_data[:music_id].present?
        if chapter.collaborator_music.present?
          chapter.collaborator_music.update(music_id: chapter_data[:music_id])
        else
          chapter.create_collaborator_music(music_id: chapter_data[:music_id])
        end
      end
    end
    redirect_to collaborator_video_details_path(@video.id), notice: 'Video chapters updated successfully'
  end

  def delete_collaborator_chapter
    collaborator_chapter = CollaboratorChapter.find(params[:id]) # Use the appropriate ID from the params
    authorize collaborator_chapter.video, :delete_collaborator_chapter?, policy_class: ProjectPolicy
    if collaborator_chapter.destroy!
      respond_to do |format|
        format.html { redirect_to collaborator_video_details_path(collaborator_chapter.video.id), notice: 'Chapter deleted successfully.' }
        format.json { render json: { message: 'Chapter deleted successfully' }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to collaborator_video_details_path(collaborator_chapter.video.id), alert: 'Failed to delete the chapter.' }
        format.json { render json: { error: 'Failed to delete the chapter' }, status: :unprocessable_entity }
      end
    end
  end

  def delete_creator_chapter
    video_chapter = VideoChapter.find(params[:id]) # Use the appropriate ID from the params
    authorize video_chapter.video, :delete_creator_chapter?, policy_class: ProjectPolicy
    if video_chapter.destroy!
      respond_to do |format|
        format.html { redirect_to participants_progress_path(video_id: @video.id), notice: 'Chapter deleted successfully.' }
        format.json { render json: { message: 'Chapter deleted successfully' }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to participants_progress_path(video_id: @video.id), alert: 'Failed to delete the chapter.' }
        format.json { render json: { error: 'Failed to delete the chapter' }, status: :unprocessable_entity }
      end
    end
  end

  def collaborator_manage_dedicace
    authorize @video, :collaborator_manage_dedicace?, policy_class: ProjectPolicy
    @dedicaces = Dedicace.all
    collaboration = Collaboration.find_by(video_id: @video.id, invited_user: current_user)
    @collaborator_dedicace = CollaboratorDedicace.find_by(video_id: @video.id, collaboration: collaboration)
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
      collaboration: collaboration
    )
    collaborator_dedicace.dedicace_id = params[:collaborator_dedicace]

    if params[:creator_end_dedication_video].present?
      collaborator_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video])
    elsif params[:creator_end_dedication_video_uploaded].present?
      collaborator_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video_uploaded])
    end

    if collaborator_dedicace.save
      VideoProcessingJob.perform_later(collaborator_dedicace.id, "CollaboratorDedicace")
      flash[:notice] = "Collaborator Dedicace successfully created!"
    else
      flash[:alert] = "Failed to create Collaborator Dedicace: #{collaborator_dedicace.errors.full_messages.to_sentence}"
    end

    redirect_to collaborator_manage_dedicace_path(@video.id)
  end

  def creator_dedicace_de_fin_post
    authorize @video, :creator_dedicace_de_fin_post?, policy_class: ProjectPolicy

    video_dedicace = VideoDedicace.find_or_initialize_by(
      video_id: @video.id,
    )

    video_dedicace.dedicace_id = params[:video_dedicace]

    if params[:creator_end_dedication_video].present?
      video_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video])
    elsif params[:creator_end_dedication_video_uploaded].present?
      video_dedicace.creator_end_dedication_video.attach(params[:creator_end_dedication_video_uploaded])
    end

    if video_dedicace.save
      VideoProcessingJob.perform_later(video_dedicace.id, "VideoDedicace")
      flash[:notice] = "Video Dedicace successfully created!"
    else
      flash[:alert] = "Failed to create Collaborator Dedicace: #{video_dedicace.errors.full_messages.to_sentence}"
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
    @video_dedicace = VideoDedicace.find_by(video_id: @video.id)
  end

  def creator_refresh_video
    authorize @video, :creator_refresh_video?, policy_class: ProjectPolicy
    # Update the status to processing
    @video.update!(concat_status: :processing)

    # Purge existing final video attachments
    @video.final_video.purge if @video.final_video.attached?
    @video.final_video_xml.purge if @video.final_video_xml.attached?

    # Enqueue the job to process the video again
    ContentDedicaceJob.perform_later(@video.id)
    flash[:notice] = "Le traitement de la vidéo a été relancé en arrière-plan."

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
      dedicace = CollaboratorDedicace.find_by(collaboration_id: collaboration_id)
      dedicace.update(approved_by_creator: ActiveModel::Type::Boolean.new.cast(collaborator_attachment[:dedicace])) if dedicace
    end

    # Update CollaboratorChapters
    if collaborator_attachment[:chapter].present?
      collaborator_attachment[:chapter].each do |chapter_id, approved|
        chapter = CollaboratorChapter.find_by(id: chapter_id, collaboration_id: collaboration_id)
        chapter.update(approved_by_creator: ActiveModel::Type::Boolean.new.cast(approved)) if chapter
      end
    end

    redirect_to participants_progress_path(video_id: @video.id), notice: 'Approvals have been updated successfully.'
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
    @video = Video.find(params[:video_id].present? ? params[:video_id] : params[:id])
  end

  def find_destinataire
    @destinataire = @video.video_destinataire
  end
end
