# app/helpers/client_notes_helper.rb
module ClientNotesHelper
  def client_note_category_badge(note)
    content_tag(:span, class: "badge bg-#{note.category_color} bg-opacity-15 text-#{note.category_color} border border-#{note.category_color} border-opacity-25 d-inline-flex align-items-center gap-1") do
      concat content_tag(:i, "", class: "bi #{note.category_icon} fs-7")
      concat note.category_label
    end
  end

  def client_note_time_ago(note)
    content_tag(:small, class: "text-muted") do
      "#{note.user.name} · #{time_ago_in_words(note.created_at)} atrás"
    end
  end
end
