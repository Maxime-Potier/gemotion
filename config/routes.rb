require "sidekiq/web"
Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"

  scope "(:locale)", locale: /#{I18n.available_locales.join('|')}/ do
    devise_for :users
    resources :users, only: %i[show edit update] # Add other actions if needed

    post "flush_and_reseed", to: "static#flush_and_reseed"
    # resources :contacts, only: [:new, :create]

    resources :contacts, only: %i[new create]

    # Video
    get "videos/back", to: "videos#go_back", as: "step_back"
    get "videos/go_to_select_chapters", to: "videos#go_to_select_chapters", as: "go_to_select_chapters"

    get "videos/start", to: "videos#start", as: "start"
    post "videos/start", to: "videos#start_post", as: "start_post"

    get "videos/occasion", to: "videos#occasion", as: "occasion"
    post "videos/occasion", to: "videos#occasion_post", as: "occasion_post"

    # get 'videos/destinataire', to: "videos#destinataire", as: "destinataire"
    # post 'videos/destinataire', to: "videos#destinataire_post", as: "destinataire_post"

    get "videos/info_destinataire", to: "videos#info_destinataire", as: "info_destinataire"
    post "videos/info_destinataire", to: "videos#info_destinataire_post", as: "info_destinataire_post"

    get "videos/destinataire_details", to: "videos#destinataire_details", as: "destinataire_details"
    post "videos/destinataire_details_post", to: "videos#destinataire_details_post", as: "destinataire_details_post"
    delete "videos/delete_destinataire/:id", to: "videos#delete_destinataire", as: "delete_destinataire"
    patch "videos/update_destinataire/:id", to: "videos#update_destinataire", as: "update_destinataire"

    get "videos/date_fin", to: "videos#date_fin", as: "date_fin"
    post "videos/date_fin", to: "videos#date_fin_post", as: "date_fin_post"

    get "videos/introduction", to: "videos#introduction", as: "introduction"
    post "videos/introduction", to: "videos#introduction_post", as: "introduction_post"

    get "videos/photo_intro", to: "videos#photo_intro", as: "photo_intro"
    post "videos/photo_intro", to: "videos#photo_intro_post", as: "photo_intro_post"
    delete "videos/drop_preview/:id", to: "videos#drop_preview", as: "drop_preview"

    get "videos/select_chapters", to: "videos#select_chapters", as: "select_chapters"
    post "videos/select_chapters", to: "videos#select_chapters_post", as: "select_chapters_post"

    get "videos/music", to: "videos#music", as: "music"
    post "videos/music", to: "videos#music_post", as: "music_post"
    patch "videos/update_video_music_type", to: "videos#update_video_music_type", as: "update_video_music_type"
    delete "videos/drop_custom_music/:id", to: "videos#drop_custom_music", as: "drop_custom_music"

    get "videos/dedicace", to: "videos#dedicace", as: "dedicace"
    post "videos/dedicace", to: "videos#dedicace_post", as: "dedicace_post"

    get "videos/share", to: "videos#share", as: "share"
    post "videos/share", to: "videos#share_post", as: "share_post"
    get "videos/skip_share", to: "videos#skip_share", as: "skip_share"

    get "videos/content", to: "videos#content", as: "content"
    post "videos/content", to: "videos#content_post", as: "content_post"
    get "videos/skip_content", to: "videos#skip_content", as: "skip_content"

    get "videos/content_dedicace", to: "videos#content_dedicace", as: "content_dedicace"
    post "videos/refresh_content_dedicace", to: "videos#refresh_content_dedicace", as: "refresh_content_dedicace"
    get "videos/:id/stream", to: "videos#stream_video", as: "stream_video"
    post "videos/content_dedicace", to: "videos#content_dedicace_post", as: "content_dedicace_post"
    get "videos/skip_content_dedicace", to: "videos#skip_content_dedicace", as: "skip_content_dedicace"

    get "videos/deadline", to: "videos#deadline", as: "deadline"
    post "videos/deadline", to: "videos#deadline_post", as: "deadline_post"
    get "videos/skip_deadline", to: "videos#skip_deadline", as: "skip_deadline"

    get "videos/dedicace_de_fin", to: "videos#dedicace_de_fin", as: "dedicace_de_fin"
    patch "/:id/videos/dedicace_de_fin_post", to: "videos#dedicace_de_fin_post", as: "dedicace_de_fin_post"
    get "videos/skip_dedicace_de_fin", to: "videos#skip_dedicace_de_fin", as: "skip_dedicace_de_fin"

    get "videos/confirmation", to: "videos#confirmation", as: "confirmation"
    post "videos/confirmation", to: "videos#confirmation_post", as: "confirmation_post"
    get "videos/skip_confirmation", to: "videos#skip_confirmation", as: "skip_confirmation"

    patch "videos/:id/update_video_slot", to: "videos#update_video_slot", as: "update_video_slot"

    get "videos/:id/get_video_slot_status", to: "videos#get_video_slot_status", as: "get_video_slot_status"

    get "videos/edit_video", to: "videos#edit_video", as: "edit_video"
    post "videos/edit_video_post", to: "videos#edit_video_post", as: "edit_video_post"
    get "videos/skip_edit_video", to: "videos#skip_edit_video", as: "skip_edit_video"
    delete "videos/delete_video_chapter/:id", to: "videos#delete_video_chapter", as: "delete_video_chapter"
    delete "videos/purge_chapter_attachment/:id", to: "videos#purge_chapter_attachment", as: "purge_chapter_attachment"

    get "videos/payment", to: "videos#payment", as: "payment"
    post "videos/payment_post", to: "videos#payment_post", as: "payment_post"

    get "videos/render_final_page", to: "videos#render_final_page", as: "render_final_page"

    get "join/videos/:id", to: "videos#join", as: "join"

    get "projects/as_creator", to: "projects#as_creator_projects", as: "as_creator_projects"
    get "projects/as_collaborator", to: "projects#as_collaborator_projects", as: "as_collaborator_projects"
    get "projects/participants_progress", to: "projects#participants_progress", as: "participants_progress"
    get "projects/collaborator_video_details/:id", to: "projects#collaborator_video_details",
                                                   as: "collaborator_video_details"

    get "projects/collaborator_manage_chapters/:id", to: "projects#collaborator_manage_chapters",
                                                     as: "collaborator_manage_chapters"
    get "projects/collaborator_manage_dedicace/:id", to: "projects#collaborator_manage_dedicace",
                                                     as: "collaborator_manage_dedicace"
    post "projects/collaborator_chapters_post", to: "projects#collaborator_chapters_post",
                                                as: "collaborator_chapters_post"
    post "projects/edit_collaborator_chapters_post", to: "projects#edit_collaborator_chapters_post",
                                                     as: "edit_collaborator_chapters_post"
    delete "projects/delete_collaborator_chapter/:id", to: "projects#delete_collaborator_chapter",
                                                       as: "delete_collaborator_chapter"
    post "projects/collaborator_dedicace_de_fin_post", to: "projects#collaborator_dedicace_de_fin_post",
                                                       as: "collaborator_dedicace_de_fin_post"

    get "projects/creator_manage_chapters/:id", to: "projects#creator_manage_chapters", as: "creator_manage_chapters"
    get "projects/creator_manage_dedicace/:id", to: "projects#creator_manage_dedicace", as: "creator_manage_dedicace"
    post "projects/creator_chapters_post", to: "projects#creator_chapters_post", as: "creator_chapters_post"
    post "projects/edit_creator_chapters_post", to: "projects#edit_creator_chapters_post",
                                                as: "edit_creator_chapters_post"
    delete "projects/delete_creator_chapter/:id", to: "projects#delete_creator_chapter", as: "delete_creator_chapter"
    post "projects/creator_dedicace_de_fin_post", to: "projects#creator_dedicace_de_fin_post",
                                                  as: "creator_dedicace_de_fin_post"
    post "projects/creator_refresh_video", to: "projects#creator_refresh_video", as: "creator_refresh_video"
    post "projects/approving_collaborator_attachments", to: "projects#approving_collaborator_attachments",
                                                        as: "approving_collaborator_attachments"
    get "projects/invite_collaborators", to: "projects#invite_collaborators", as: "invite_collaborators"
    post "projects/invite_collaborators_post", to: "projects#invite_collaborators_post", as: "invite_collaborators_post"

    delete "projects/delete_collaboration/:id", to: "projects#delete_collaboration", as: "delete_collaboration"
    patch "projects/:id/modify_deadline", to: "projects#modify_deadline", as: "modify_deadline"
    patch "projects/:id/close_project", to: "projects#close_project", as: "close_project"

    get "videos/:id/concat_status", to: "videos#concat_status", as: "video_concat_status"

    # Static pages
    get "about", to: "static#about", as: "about"
    get "pricing", to: "static#pricing", as: "pricing"

    # Users profile pages
    get "profile", to: "users#show", as: :profile

    # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
    # Can be used by load balancers and uptime monitors to verify that the app is live.
    get "up" => "rails/health#show", as: :rails_health_check

    # Defines the root path route ("/")
    root "static#home"
  end
end
