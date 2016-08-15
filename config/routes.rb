Rails.application.routes.draw do
  resources :blocks
  devise_for :users
  root 'interface#index'
  resources :activities
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
