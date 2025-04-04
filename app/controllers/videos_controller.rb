require "fileutils"
require "zip"
class VideosController < ApplicationController
  before_action :authenticate_user!, except: :join
  before_action :select_video, except: %i[go_back go_to_select_chapters join update_video_music_type
                                          concat_status delete_video_chapter purge_chapter_attachment drop_custom_music
                                          drop_preview stream_video delete_destinataire update_destinataire]
  before_action :define_chapter_type, only: %i[select_chapters select_chapters_post]
  before_action :define_music, only: %i[music music_post edit_video]
  before_action :define_dedicace, only: %i[dedicace dedicace_post]
  before_action :select_join_video, only: %i[join]
  before_action :define_video_chapters, only: %i[content content_post]

  def start
    # authorize @video, :start?, policy_class: VideoPolicy

    return if @video.nil?
    return unless @video.stop_at != "start_edit"

    if @video.stop_at == "start_edit"
      redirect_to start_path
    elsif @video.stop_at == "start"
      redirect_to occasion_path
    elsif @video.current_step != "start"
      redirect_to send("#{@video.current_step}_path"),
                  notice: "Reprenez votre vidéo en cours."
    end

    # TODO: delete current video if user confirmation
  end

  ##
  # Cette méthode pose problème si l'on utilise turbo car le préchargement
  # provoque le recul en arrière. Il faut donc desactiver turbo sur les liens
  # souhaitant ce servir de step_back_path.
  # Utilise le template dans videos/shared/_back_button.html.erb pour récupérer
  # un lien fonctionnel
  def go_back
    @video = current_user.videos.where.not(project_status: %i[finished closed]).order(created_at: :desc).first
    authorize @video, :go_back?, policy_class: VideoPolicy
    redirect_to start_path, alert: "Aucune vidéo trouvé." if @video.nil?
    @video.stop_at = @video.current_step == "start" ? "start_edit" : @video.previous_step
    if @video.save
      if @video.stop_at == "start_edit"
        redirect_to start_path
      elsif @video.stop_at == "start"
        redirect_to occasion_path
      else
        redirect_to send("#{@video.next_step}_path")
      end
    else
      redirect_to send("#{@video.current_step}_path"), alert: "Impossible de revenir en arrière"
    end
  end

  def go_to_select_chapters
    @video = current_user.videos.where.not(project_status: %i[finished closed]).order(created_at: :desc).first
    @video.update(stop_at: "photo_intro")
    redirect_to select_chapters_path, alert: "Aucune vidéo trouvé."
  end

  def start_post
    if current_user.videos.where.not(project_status: %i[finished closed]).count == 0 || current_user.videos.count == 0
      @video = Video.new(user: current_user)
      @video.user = current_user
      skip_authorization
      return render start_path, status: :unprocessable_entity if params[:video_type].nil?

      @video.video_type = params[:video_type].downcase

      @video.stop_at = @video.way.first
      @video.generate_token

    else
      authorize @video, :start_post?, policy_class: VideoPolicy
      @video.video_type = params[:video_type].downcase
      @video.stop_at = @video.way.first
    end

    if @video.validate_start && @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      render start_path, status: :unprocessable_entity
    end
  end

  def occasion_post
    authorize @video, :occasion_post?, policy_class: VideoPolicy
    @video.occasion = params[:occasion]
    @video.stop_at = @video.next_step

    if @video.validate_occasion && @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      @video.update(stop_at: @video.current_step)
      render occasion_path, status: :unprocessable_entity
    end
  end

  def destinataire_post
    authorize @video, :destinataire_post?, policy_class: VideoPolicy
    @vd = @video.video_destinataires.new(genre: params[:sexe_destinataire])
    @video.stop_at = @video.next_step

    if @video.validate_destinataire(@vd) && @vd.save && @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      @video.update(stop_at: @video.current_step)
      render destinataire_path, status: :unprocessable_entity
    end
  end

  def info_destinataire
    authorize @video, :info_destinataire?, policy_class: VideoPolicy
    @video_destinataires = @video.video_destinataires.order(created_at: :asc)
  end

  def info_destinataire_post
    authorize @video, :info_destinataire_post?, policy_class: VideoPolicy
    # for skip destinataire page
    @vd = VideoDestinataire.new(genre: 2, video: @video)
    ##############################
    @vd.age = params[:age_destinataire]
    @vd.name = params[:name_destinataire]
    @vd.more_info = params[:more_info_destinataire]
    @vd.passions_and_hobbies = params[:passions_and_hobbies]
    @vd.personality_description = params[:personality_description]
    @vd.favorite_quotes = params[:favorite_quotes]

    @video.stop_at = @video.next_step unless params[:add_more_destinataire].present? && params[:add_more_destinataire]

    more_destinataire = params[:add_more_destinataire].present? && params[:add_more_destinataire]

    is_empty_params = params[:age_destinataire].blank? &&
                      params[:name_destinataire].blank? &&
                      params[:more_info_destinataire].blank? &&
                      params[:passions_and_hobbies].blank? &&
                      params[:personality_description].blank? &&
                      params[:favorite_quotes].blank?

    if @video.validate_info_destinataire(@vd)
      if @vd.save
        if !more_destinataire
          @video.update(stop_at: @video.current_step)
          redirect_to destinataire_details_path, turbo: false
        else
          redirect_to info_destinataire_path
        end
      else
        redirect_to info_destinataire_path, alert: "Veuillez remplir tous les champs obligatoires."
      end
    elsif is_empty_params && @video.video_destinataires.count > 0
      @video.update(stop_at: @video.current_step)
      redirect_to destinataire_details_path, turbo: false
    else
      redirect_to info_destinataire_path, alert: "Veuillez remplir tous les champs obligatoires."
    end

    nil if params[:special_request_destinataire].nil?
    # TODO: send email to PO.
  end

  def destinataire_details
    authorize @video, :destinataire_details?, policy_class: VideoPolicy
    @video_destinataires = @video.video_destinataires.order(created_at: :asc)
  end

  def destinataire_details_post
    # authorize @video, :skip_share?
    if params[:special_request_destinataire].present?
      @video.theme = "specific_request"
      @video.theme_specific_request = params[:special_request_destinataire]
    end

    @video.stop_at = @video.next_step

    if @video.save
      redirect_to send("#{@video.next_step}_path"), turbo: false
    else
      @video.update(stop_at: @video.current_step)
      render destinataire_details_path, status: :unprocessable_entity
    end
  end

  def delete_destinataire
    destinataire = VideoDestinataire.find(params[:id]) # Use the appropriate ID from the params
    video = Video.find(destinataire.video_id)
    authorize video, :delete_destinataire?, policy_class: VideoPolicy
    if destinataire.destroy
      redirect_to destinataire_details_path, notice: "Destinataire deleted successfully.", turbo: false
    else
      redirect_to destinataire_details_path, alert: "Vous n'êtes pas autorisé à supprimer ce destinataire.",
                                             turbo: false
    end
  end

  def update_destinataire
    destinataire = VideoDestinataire.find(params[:id]) # Use the appropriate ID from the params
    video = Video.find(destinataire.video_id)
    authorize video, :update_destinataire?, policy_class: VideoPolicy

    destinataire.age = params[:age_destinataire]
    destinataire.name = params[:name_destinataire]
    destinataire.more_info = params[:more_info_destinataire]
    destinataire.passions_and_hobbies = params[:passions_and_hobbies]
    destinataire.personality_description = params[:personality_description]
    destinataire.favorite_quotes = params[:favorite_quotes]

    if destinataire.save
      redirect_to destinataire_details_path,
                  notice: "Le destinataire a \u00E9t\u00E9 mis \u00E0 jour avec succ\u00E8s.", turbo: false
    else
      redirect_to destinataire_details_path, alert: "Vous n'êtes pas autorisé à mettre à jour ce destinataire.",
                                             turbo: false
    end
  end

  def date_fin_post
    authorize @video, :date_fin_post?, policy_class: VideoPolicy
    return render date_fin_path, status: :unprocessable_entity if params[:end_date].blank?

    @video.end_date = DateTime.parse(params[:end_date])
    @video.stop_at = @video.next_step

    if @video.validate_date_fin && @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      @video.update(stop_at: @video.current_step)
      render date_fin_path, status: :unprocessable_entity
    end
  end

  def introduction_post
    authorize @video, :introduction_post?, policy_class: VideoPolicy
    @video.introduction_video = params[:theme].to_i
    @video.theme_specific_request = params[:special_request]
    @video.stop_at = @video.next_step
    if @video.validate_introduction && @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      @video.update(stop_at: @video.current_step)
      render introduction_path, status: :unprocessable_entity
    end
  end

  def photo_intro
    authorize @video, :photo_intro?, policy_class: VideoPolicy
    @ordered_previews = @video.previews.includes(image_attachment: :blob).sort_by do |preview|
      @video.previews_order.index(preview.image.filename.to_s)
    end
  end

  def photo_intro_post
    authorize @video, :photo_intro_post?, policy_class: VideoPolicy

    # Normalize uploaded previews into an array
    uploaded_previews = if params[:previews].is_a?(ActionDispatch::Http::UploadedFile)
                          [params[:previews]]
                        elsif params[:previews].respond_to?(:values)
                          params[:previews].values
                        else
                          []
                        end.reject(&:blank?)

    # Parse the images order
    ordered_previews = params[:images_order]&.split(",") || []
    current_previews = @video.video_previews.includes(:preview).to_a

    # Ensure the total number of previews does not exceed the limit
    if current_previews.size + uploaded_previews.size > 3
      flash[:alert] = "Vous ne pouvez pas ajouter plus de 3 aperçus."
      redirect_to photo_intro_path and return
    end

    # Update the order of existing previews
    current_previews.each do |video_preview|
      filename = video_preview.preview.image.filename.to_s
      if (new_order_index = ordered_previews.index(filename))
        video_preview.update(order: new_order_index)
      end
      
      # Update text overlay properties for existing previews
      if params[:preview_overlay] && params[:preview_overlay][video_preview.preview.id.to_s]
        preview_overlay = params[:preview_overlay][video_preview.preview.id.to_s]
        video_preview.preview.update(
          text: preview_overlay[:text],
          text_position: preview_overlay[:text_position],
          start_time: 0,#preview_overlay[:start_time],
          duration: 3,#preview_overlay[:duration],
          font_type: preview_overlay[:font_type],
          font_style: preview_overlay[:font_style],
          font_size: preview_overlay[:font_size],
          animation: preview_overlay[:animation],
          text_color: preview_overlay[:text_color]
        )
      end
    end

    # Add new previews and assign order based on their position in `images_order`
    # Also handle text overlay data for new previews
    uploaded_previews.each do |preview_file|
      next if preview_file.blank?

      # Get position from filename in ordered_previews
      position = 1
      positions = []
      positions = params[:previews].values
      keys = params[:previews].keys
      positions.each_with_index do |value,index|
        position = keys[index] if value == preview_file
      end

      order_index = ordered_previews.index(preview_file.original_filename)
      
      # Create the preview with text overlay properties if available
      preview_attrs = { image: preview_file }
      
      # Check if we have text overlay data for this position
      if params[:new_preview_overlay] && params[:new_preview_overlay][position.to_s]
        overlay_data = params[:new_preview_overlay][position.to_s]
        preview_attrs.merge!(
          text: overlay_data[:text],
          text_position: overlay_data[:text_position],
          start_time: overlay_data[:start_time],
          duration: overlay_data[:duration],
          font_type: overlay_data[:font_type],
          font_style: overlay_data[:font_style],
          font_size: overlay_data[:font_size],
          animation: overlay_data[:animation],
          text_color: overlay_data[:text_color]
        )
      end
      
      preview = Preview.create(preview_attrs)
      @video.video_previews.create(preview: preview, order: order_index) if order_index
    end

    # Re-assign previews_order for the video model
    @video.previews_order = ordered_previews
    @video.stop_at = @video.next_step if @video.validate_photo_intro

    # Save and navigate to the next step
    if @video.validate_photo_intro && @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      flash[:alert] = "Vous devez sélectionner au moins une photo"
      @video.update(stop_at: @video.current_step)
      redirect_to photo_intro_path
    end
  end

  def drop_preview
    preview = Preview.find(params[:id])
    video = Video.find(params[:video_id])
    authorize video, :drop_preview?, policy_class: VideoPolicy
    if preview.destroy
      respond_to do |format|
        format.json do
          render json: { message: "L'image d'introduction de la photo a été supprimée avec succès" }, status: :ok
        end
      end
    else
      respond_to do |format|
        format.json do
          render json: { error: "Échec de la suppression de l'image d'introduction de la photo" },
                 status: :unprocessable_entity
        end
      end
    end
  end

  def select_chapters
    authorize @video, :select_chapters?, policy_class: VideoPolicy
  end

  def select_chapters_post
    authorize @video, :select_chapters_post?, policy_class: VideoPolicy
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

      @video.update(stop_at: @video.next_step)
      p "*" * 1000
      redirect_to send("#{@video.next_step}_path"), turbo: false

    else
      @video.update(stop_at: @video.current_step)
      @chapterstype = ChapterType.all
      render select_chapters_path, status: :unprocessable_entity
    end
  end

  def music_post
    authorize @video, :music_post?, policy_class: VideoPolicy
    # Check for params indicating the whole video or chapters
    if params[:music].nil? && params.keys.none? { |key| key.start_with?("music_") }
      flash[:alert] = "Vous devez sélectionner au moins une musique"
      return render music_path, status: :unprocessable_entity
    end

    @video.special_request_music = params[:special_request_music] if params[:special_request_music]

    # Handle the "whole video" case
    if params[:music]
      music = Music.find_by(id: params[:music])
      if music.nil?
        flash[:alert] = "Sélection incorrecte. La musique n'existe pas."
        return render music_path, status: :unprocessable_entity
      end
      @video.music = music
    end

    # Handle the "by chapters" case
    params.each do |key, value|
      if key.start_with?("music_")
        chapter_id = key.split("_").last.to_i
        music_id = value.to_i

        video_chapter = @video.video_chapters.find_by(id: chapter_id)
        if video_chapter
          music = Music.find_by(id: music_id)
          if video_chapter.custom_music.attached? || (params["custom_music_#{video_chapter.id}"].is_a?(ActionDispatch::Http::UploadedFile) && params["custom_music_#{video_chapter.id}"].present?)
          elsif music
            video_chapter.video_music&.destroy
            VideoMusic.create(music:, video_chapter:)
          else
            flash[:alert] = "Musique non trouvée pour le chapitre #{chapter_id}."
            return render music_path, status: :unprocessable_entity
          end
        end
      elsif key.start_with?("custom_music_")
        chapter_id = key.split("_").last.to_i
        music_file = value
        video_chapter = @video.video_chapters.find_by(id: chapter_id)
        if video_chapter
          # Save the custom music to a persistent location
          music_path = Rails.root.join("tmp", "custom_music_#{video_chapter.id}.mp3")
          File.open(music_path, "wb") do |file|
            file.write(music_file.read)
          end

          # Attach the file to the video chapter and enqueue the job
          video_chapter.custom_music.attach(io: File.open(music_path), filename: music_file.original_filename)
          MusicProcessingJob.perform_later("VideoChapter", video_chapter.id, music_path.to_s)
        end
      end
    end

    @video.stop_at = @video.next_step

    if @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      @video.update(stop_at: @video.current_step)
      render music_path, status: :unprocessable_entity
    end
  end

  def drop_custom_music
    @video = Video.find(params[:video_id])
    authorize @video, :drop_custom_music?, policy_class: VideoPolicy

    video_chapter = VideoChapter.find(params[:id])

    if video_chapter.custom_music.attached?
      video_chapter.custom_music.purge # Purge the attached file
      video_chapter.update(waveform: nil) # Clear the waveform field
    end

    render json: { message: "Music and waveform deleted successfully." }, status: :ok
  end

  def dedicace_post
    authorize @video, :dedicace_post?, policy_class: VideoPolicy
    if params[:dedicace].nil?
      flash[:alert] = "Vous devez séléctionnez une dedicace"
      return render dedicace_path, status: :unprocessable_entity
    end

    @video.special_request_dedicace = params[:special_request_dedicace] if params[:special_request_dedicace]

    # Utilisation de find_by pour avoir un objet nil si pas trouvé.
    dedicace = Dedicace.find_by(id: params[:dedicace])
    if dedicace.nil?
      flash[:alert] = "Sélection incorrecte. La dedicace n'existe pas."
      return render dedicace_path, status: :unprocessable_entity
    end

    @video.dedicace = dedicace
    @video.stop_at = @video.next_step

    if @video.save
      @video.video_dedicace.update(dedicace:) if @video.video_dedicace.present?
      redirect_to send("#{@video.next_step}_path")
    else
      @video.update(stop_at: @video.current_step)
      render dedicace_path, status: :unprocessable_entity
    end
  end

  def share_post
    authorize @video, :share_post?, policy_class: VideoPolicy
    # Le mailer fonctionne mais pas le join
    email = params[:email]
    if email.blank?
      flash[:alert] = "Un email doit être indiqué pour envoyer l'invitation."
      return render share_path, status: :unprocessable_entity
    end

    # create Collab obj
    collab_user = User.find_by_email(params[:email])
    if collab_user == @video.user
      flash[:alert] = "Il s'agit de l'e-mail du créateur du projet, veuillez utiliser l'e-mail correct."
      return render share_path, status: :unprocessable_entity
    end

    @video.update(video_type: :colab) # update to collab if was solo before
    collaboration = Collaboration.create!(
      video: @video,
      inviting_user: current_user,
      invited_email: params[:email],
      invited_user: collab_user # may be nil if user doesn't exist yet
    )

    InvitationMailer.with(url: join_url(@video.token), email:).send_invitation.deliver_later
    flash[:notice] = "Invitation envoyé."
    redirect_to share_path
  end

  def join
    if current_user.present? && @video.user != current_user
      @video.update(video_type: :colab) # update to collab if was solo before
      @existing_collaboration = Collaboration.find_by(
        video: @video,
        invited_user: current_user
      )
      if @existing_collaboration.nil?
        collaboration = Collaboration.create!(
          video: @video,
          inviting_user: @video.user,
          invited_email: current_user.email,
          invited_user: current_user
        )
      end
    else
      session[:collab_video_id] = @video.id # Store the video ID for later redirection
      redirect_to new_user_session_path
    end
  end

  def skip_share
    # authorize @video, :skip_share?
    skip_element(share_path)
  end

  def content_post
    authorize @video, :content_post?, policy_class: VideoPolicy

    # Check if all chapters in params have empty inputs, but records already exist in the DB
    all_empty = params.keys.grep(/^\d+$/).all? do |key|
      video_chapter = @video.video_chapters.find_by(id: key)
      next true unless video_chapter # Skip if video chapter doesn't exist

      # Check if the DB already has videos, photos, or orders
      db_has_content = video_chapter.videos.attached? || video_chapter.photos.attached? ||
                       video_chapter.photos_order.present? || video_chapter.videos_order.present?

      # Compare database content with incoming empty params
      params_empty = params[key]["videos"] == [""] && params[key]["photos"] == [""] &&
                     params[key]["images_order"].blank? && params[key]["videos_order"].blank?

      db_has_content && params_empty
    end

    if all_empty
      flash[:notice] = "No changes made. Proceeding to the next step."
      return skip_element(content_path)
    end

    # Iterate over chapter-specific keys (e.g., "28", "29", "30")
    params.each do |key, value|
      # Skip unrelated keys
      next unless key.match?(/^\d+$/)

      video_chapter = @video.video_chapters.find_by(id: key)
      next unless video_chapter

      # Attach videos
      if value["videos"].present? && value["videos"] != [""]
        video_chapter.videos.purge
        value["videos"].reject(&:blank?).each do |video|
          video_chapter.videos.attach(video)
        end
      end

      # Attach photos
      if value["photos"].present? && value["photos"] != [""]
        video_chapter.photos.purge
        value["photos"].reject(&:blank?).each do |photo|
          video_chapter.photos.attach(photo)
        end
      end

      # Handle ordering for photos
      if value["images_order"].present?
        # image_ids = parse_order(params[:images_order], video_chapter.photos)
        video_chapter.photos_order = value["images_order"]
      end

      # Handle ordering for videos
      if value["videos_order"].present?
        # video_ids = parse_order(params[:videos_order], video_chapter.videos)
        video_chapter.videos_order = value["videos_order"]
      end

      video_chapter.save
    end

    flash[:notice] = "Content added."
    redirect_to content_path
  end

  def skip_content
    # authorize @video, :skip_content?
    skip_element(content_path)
  end

  def content_dedicace
    authorize @video, :content_dedicace?, policy_class: VideoPolicy
    # ContentDedicaceJob.perform_later(@video.id)

    # Check if a refresh has been requested
    if params[:refresh]
      # Update the status to processing
      @video.update!(concat_status: :processing)

      # Purge existing final video attachments
      @video.final_video.purge if @video.final_video.attached?
      @video.final_video_xml.purge if @video.final_video_xml.attached?

      # Enqueue the job to process the video again
      ContentDedicaceJob.perform_later(@video.id)
      flash[:notice] = "Le traitement de la vidéo a été relancé en arrière-plan."

      # Redirect to the same action without the refresh parameter
      redirect_to content_dedicace_path and return
    end
    # Check if the final video is already attached
    if @video.final_video_with_watermark.attached?
      @final_video_url = url_for(@video.final_video_with_watermark)
    elsif @video.concat_status == "processing"
      # Start processing if no final video exists
      flash[:notice] = "Le traitement de la vidéo est déjà en cours."
    else # Check if not already processing
      @video.update!(concat_status: :processing)
      ContentDedicaceJob.perform_later(@video.id)
      flash[:notice] = "Le traitement de la vidéo a été lancé en arrière-plan."
    end
  end

  def stream_video
    video = Video.find(params[:id])
    authorize video, :content_dedicace?, policy_class: VideoPolicy

    if video.final_video.attached?
      response.headers["Content-Type"] = video.final_video.content_type
      response.headers["Content-Disposition"] = "inline" # Prevent download dialog
      response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
      response.headers["Pragma"] = "no-cache"
      response.headers["X-Content-Type-Options"] = "nosniff"

      send_data video.final_video.download, disposition: "inline"
    else
      head :not_found
    end
  end

  def dedicace_de_fin
    authorize @video, :dedicace_de_fin?, policy_class: VideoPolicy
    @dedicace = @video.dedicace
    @video_dedicace = @video.video_dedicace
  end

  def dedicace_de_fin_post
    # @dedicace = Dedicace.find(params[:id])
    # video = Video.find_by(dedicace_id: params[:id])
    authorize @video, :dedicace_de_fin_post?, policy_class: VideoPolicy

    # position = params[:dedicace][:car_position]

    # @video.stop_at = @video.next_step

    # if @video.save
    #   redirect_to send("#{@video.next_step}_path")
    # else
    #   @video.update(stop_at: @video.current_step)
    #   render dedicace_path, status: :unprocessable_entity
    # end
    unless params[:dedicace].present?
      skip_element(dedicace_de_fin_path)
      return
    end
    if params[:dedicace].present? &&
       params[:dedicace][:creator_end_dedication_video].present? || params[:dedicace][:creator_end_dedication_video_uploaded].present?
      file = params[:dedicace][:creator_end_dedication_video].presence || params[:dedicace][:creator_end_dedication_video_uploaded]
      video_dedicace = VideoDedicace.find_or_initialize_by(video: @video, dedicace: @video.dedicace)
      video_dedicace.creator_end_dedication_video.attach(file)
      # @dedicace.update(car_position: position)
      if video_dedicace.save
        VideoProcessingJob.perform_later(video_dedicace.id, "VideoDedicace")
        skip_element(dedicace_de_fin_path)
      else
        render :edit, alert: "\u00C9chec de la mise \u00E0 jour de la vid\u00E9o."
      end
    else
      redirect_to dedicace_de_fin_path, alert: "Aucun fichier vid\u00E9o fourni."
    end
  end

  def skip_dedicace_de_fin
    # authorize @video, :skip_content_dedicace?
    skip_element(dedicace_de_fin_path)
  end

  def confirmation
    authorize @video, :confirmation?, policy_class: VideoPolicy
  end

  def confirmation_post
    authorize @video, :confirmation_post?, policy_class: VideoPolicy
    # Le mailer fonctionne mais pas le join
    email = params[:email]
    if email.blank?
      flash[:alert] = "Un email doit être indiqué pour envoyer l'invitation."
      return render confirmation_path, status: :unprocessable_entity
    end

    collab_user = User.find_by_email(params[:email])
    if collab_user == @video.user
      flash[:alert] = "Il s'agit de l'e-mail du créateur du projet, veuillez utiliser l'e-mail correct."
      return render share_path, status: :unprocessable_entity
    end

    @video.update(video_type: :colab) # update to collab if was solo before
    collaboration = Collaboration.create!(
      video: @video,
      inviting_user: current_user,
      invited_email: params[:email],
      invited_user: collab_user # may be nil if user doesn't exist yet
    )

    InvitationMailer.with(url: join_url(@video.token), email:).send_invitation.deliver_later
    flash[:notice] = "Invitation envoyé."
    redirect_to confirmation_path
  end

  def skip_confirmation
    skip_element(confirmation_path)
  end

  def deadline
    authorize @video, :deadline?, policy_class: VideoPolicy
  end

  def deadline_post
    authorize @video, :deadline_post?, policy_class: VideoPolicy
    return render deadline_path, status: :unprocessable_entity if params[:end_date].blank?

    @video.end_date = DateTime.parse(params[:end_date])
    @video.stop_at = @video.next_step

    if @video.validate_date_fin && @video.save
      redirect_to send("#{@video.next_step}_path")
    else
      @video.update(stop_at: @video.current_step)
      render deadline_path, status: :unprocessable_entity
    end
  end

  def skip_deadline
    skip_element(deadline_path)
  end

  def edit_video
    authorize @video, :edit_video?, policy_class: VideoPolicy
    @chapters = @video.video_chapters.order(:order).includes(:chapter_type, videos_attachments: :blob,
                                                                            photos_attachments: :blob)
  end

  def edit_video_post
    authorize @video, :edit_video_post?, policy_class: VideoPolicy

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

          # Purge the oldest video if there are already 2 videos
          chapter.videos.first.purge if chapter.videos.count >= 2

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

        # Purge the oldest photo if there are already 2 photos
        chapter.photos.first.purge if chapter.photos.count >= 2

        chapter.photos.attach(photo)
      end
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
          # Save the custom music file temporarily
          music_path = Rails.root.join("tmp", "custom_music_#{video_chapter.id}.mp3")
          File.open(music_path, "wb") do |file|
            file.write(music_file.read)
          end

          # Attach the file to the video chapter and enqueue the job
          video_chapter.custom_music.attach(io: File.open(music_path), filename: music_file.original_filename)
          MusicProcessingJob.perform_later("VideoChapter", video_chapter.id, music_path.to_s)
        else
          flash[:alert] ||= []
          flash[:alert] << "Fichier de musique personnalisé manquant ou chapitre introuvable pour l'ID #{chapter_id}."
        end
      end
    end

    redirect_to skip_edit_video_path
    # redirect_to edit_video_path, notice: 'Video chapters updated successfully'
  end

  def payment
    authorize @video, :payment?, policy_class: VideoPolicy
    @duration_in_minutes = Video.calculate_duration(@video.final_video_duration) # Replace with your logic to fetch duration
    @amount = Video.calculate_price(@duration_in_minutes)
    @stripe_publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]
  end

  def payment_post
    authorize @video, :payment_post?, policy_class: VideoPolicy
    duration_in_minutes = Video.calculate_duration(@video.final_video_duration)
    amount = Video.calculate_price(duration_in_minutes) * 100 # Convert to cents

    begin
      charge = Stripe::Charge.create(
        amount:,
        currency: "eur",
        description: "Payment for video rendering (#{duration_in_minutes} minutes)",
        source: params[:stripeToken],
        metadata: {
          video_id: @video.id,
          user_email: current_user.email # Example of including the user's email
        }
      )

      # Save payment record and update video status
      @video.update!(paid: true, project_status: :finished) # Ensure `paid` is a boolean in the Video model
      redirect_to participants_progress_path(video_id: @video.id), notice: "Paiement r\u00E9ussi!"
    rescue Stripe::CardError => e
      flash[:alert] = e.message
      redirect_to payment_path
    end
  end

  # def render_final_page
  #   authorize @video, :render_final_page?, policy_class: VideoPolicy
  #   # Check if the final video is already attached
  #   if @video.final_video.attached?
  #     @final_video_url = url_for(@video.final_video)
  #     @zip_url = url_for(@video.final_video_xml) if @video.final_video_xml.attached?
  #   else
  #     # Start processing if no final video exists
  #     unless @video.concat_status == 'processing' # Check if not already processing
  #       @video.update!(concat_status: :processing)
  #       ContentDedicaceJob.perform_later(@video.id)
  #       flash[:notice] = "Le traitement de la vidéo a été lancé en arrière-plan."
  #     else
  #       flash[:notice] = "Le traitement de la vidéo est déjà en cours."
  #     end
  #   end
  # end

  def skip_edit_video
    # authorize @video, :skip_content_dedicace?
    skip_element(edit_video_path)
  end

  def delete_video_chapter
    video_chapter = VideoChapter.find(params[:id]) # Use the appropriate ID from the params
    authorize video_chapter.video, :delete_video_chapter?, policy_class: VideoPolicy
    if video_chapter.destroy
      respond_to do |format|
        format.html { redirect_to edit_video_path, notice: "Chapitre supprim\u00E9 avec succ\u00E8s." }
        format.json { render json: { message: "Chapitre supprim\u00E9 avec succ\u00E8s." }, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to edit_video_path, alert: "\u00C9chec de la suppression du chapitre." }
        format.json do
          render json: { error: "\u00C9chec de la suppression du chapitre." }, status: :unprocessable_entity
        end
      end
    end
  end

  def purge_chapter_attachment
    attachment = ActiveStorage::Attachment.find_by(id: params[:id])
    if attachment.nil?
      return respond_to do |format|
        format.json { render json: { error: "Attachment not found" }, status: :not_found }
      end
    end
    authorize attachment.record.video, :purge_chapter_attachment?, policy_class: VideoPolicy
    attachment.purge
    respond_to do |format|
      format.json { render json: { message: "Attachment deleted successfully" }, status: :ok }
    end
  end

  def get_video_duration(video_path)
    # authorize @video, :get_video_duration?
    output = `ffprobe -i #{video_path} -show_entries format=duration -v quiet -of csv="p=0"`
    output.strip
  end

  def content_dedicace_post
    authorize @video, :content_dedicace_post?, policy_class: VideoPolicy
    params[:contents].each do |file|
      dc = @video.dedicace_contents.create(position: @video.dedicace_contents.count)
      dc.content.attach(file)
    end

    flash[:notice] = "Contenu ajouté."
    redirect_to content_dedicace_path
  end

  def skip_content_dedicace
    # authorize @video, :skip_content_dedicace?
    skip_element(content_dedicace_path)
  end

  def update_video_music_type
    @video = Video.find(params[:id])
    authorize @video, :update_video_music_type?, policy_class: VideoPolicy

    if @video.update(music_type: params[:video][:music_type])
      head :no_content # Respond with a 204 No Content status to avoid template rendering
    else
      render plain: "Failed to update music type", status: :unprocessable_entity
    end
  end

  def concat_status
    video = Video.find(params[:id])
    authorize video, :concat_status?, policy_class: VideoPolicy
    render json: { concat_status: video.concat_status }
  end

  private

  def generate_fcpxml(final_video_path, video_path, music_path)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE fcpxml>
      <fcpxml version="1.8">
        <resources>
          <format id="r1" name="FFVideoFormat1080p24" frameDuration="1001/24000s" width="1920" height="1080"/>
          <asset id="video" src="#{video_path}" start="0s" duration="3600s" hasAudio="1" hasVideo="1"/>
          <asset id="music" src="#{music_path}" start="0s" duration="3600s" hasAudio="1" hasVideo="0"/>
          <asset id="final_video" src="#{final_video_path}" start="0s" duration="3600s" hasAudio="1" hasVideo="1"/>
        </resources>
        <library>
          <event name="Event">
            <project name="Project">
              <sequence duration="3600s" format="r1">
                <spine>
                  <asset-clip name="Final Video" offset="0s" ref="final_video" duration="3600s" start="0s">
                  </asset-clip>
                  <asset-clip name="Music" offset="0s" ref="music" duration="3600s" start="0s">
                  </asset-clip>
                </spine>
              </sequence>
            </project>
          </event>
        </library>
      </fcpxml>
    XML
  end

  def select_video
    @video = current_user.videos.where.not(project_status: %i[finished closed]).order(created_at: :desc).first
    # On check si une vidéo existe

    if @video.nil?
      redirect_to start_path, alert: "Aucune vidéo trouvé." unless request.path == start_path
    # Si une vidéo existe, on doit être sur la bonne étape
    elsif @video.current_step == "start"
      nil
    elsif ![@video.next_step.downcase, "#{@video.next_step.downcase}_post",
            "skip_#{@video.next_step.downcase}"].include?(params[:action].downcase)
      if params[:continue].present? && params[:continue]
        redirect_to send("#{@video.next_step}_path"), turbo: false
      else
        redirect_to send("#{@video.next_step}_path"),
                    alert: "Vous devez finaliser cette étape avant de passer à la prochaine.", turbo: false
      end

    end
  end

  def define_chapter_type
    # On va cherche la query directement dans SQL
    q_results = ActiveRecord::Base.connection.exec_query('
      SELECT DISTINCT "chapter_types".id, "chapter_types".created_at, "video_chapters".text, "video_chapters".slide_color, "video_chapters".text_family, "video_chapters".text_style, "video_chapters".text_size
      FROM "chapter_types"
      LEFT OUTER JOIN "video_chapters" ON "video_chapters"."chapter_type_id" = "chapter_types"."id" AND video_chapters.video_id = $1
      ORDER BY "chapter_types".created_at ASC',
                                                         "selectChapterWithData",
                                                         [@video.id])
    # On recupere le resultat est filtre pour n'avoir que les ID de chapters_types
    r_only_id = q_results.rows.map { |v| v[0] }
    # On recupere les ChaptersType (le modèle Rails).
    chapter_types = ChapterType.where(id: r_only_id)
    # On transforme cela en hash (pour effectuer une accessation en 0(n))
    chapter_types_h = chapter_types.index_by { |ct| ct.id }

    @chapterstype = q_results.as_json.map do |k|
      { ct: chapter_types_h[k["id"]], text: k["text"],
        slide_color: k["slide_color"], text_family: k["text_family"],
        text_style: k["text_style"], text_size: k["text_size"],
        select: k["text"].present? }
    end
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

  def define_dedicace
    @dedicaces = Dedicace.all
  end

  def select_join_video
    @video = Video.find_by!(token: params[:id])
  end

  def define_video_chapters
    @video_chapters = @video.video_chapters
  end

  def skip_element(error_path)
    @video.stop_at = @video.next_step

    if @video.save
      redirect_to send("#{@video.next_step}_path"), turbo: false
    else
      @video.update(stop_at: @video.current_step)
      render error_path, status: :unprocessable_entity
    end
  end

  # Helper method to parse order and ensure matching with attachment IDs
  def parse_order(order_param, attachments)
    order_param.split(",").map do |filename|
      attachments.find { |attachment| attachment.blob.filename.to_s == filename }&.blob_id
    end.compact
  end
end
