require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_contact_url
    assert_response :success
  end

  test "renders the contact form in English" do
    get new_contact_url(locale: :en)

    assert_response :success
    assert_select "h1", text: /Contact us/i
    assert_select "input[placeholder='First and last name*']"
    assert_select "textarea[placeholder='Your question*']"
    assert_select "input[type='submit'][value='Send']"
    assert_select "form[action='#{contacts_path(locale: :en)}'][method='post']"
  end

  test "renders the contact form in French" do
    get new_contact_url(locale: :fr)

    assert_response :success
    assert_select "h1", text: /Contactez-nous/i
    assert_select "input[placeholder='Nom et prénom*']"
    assert_select "textarea[placeholder='Votre question*']"
    assert_select "input[type='submit'][value='Envoyer']"
  end

  test "should create contact" do
    assert_difference("Contact.count", 1) do
      post contacts_url, params: {
        contact: {
          name: "Test User",
          email: "test@example.com",
          message: "Test message"
        }
      }
    end

    assert_redirected_to new_contact_url
  end
end
