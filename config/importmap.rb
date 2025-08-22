pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.2/modular/sortable.core.esm.js"
pin "bootstrap", integrity: "sha384-Hea0Yk7N2rQhmxzzIGikclw/jBEhpCDFFXi+rlgF1qZtC7eAazBGapuqKzAe6yXQ" # @5.3.7
pin "@popperjs/core", to: "@popperjs--core.js", integrity: "sha384-bfekMOfeUlr1dHZfNaAFiuuOeD7r+Qh45AQ2HHJY7EAAI4QGJ6qx1Qq9gsbvS+60" # @2.11.8
