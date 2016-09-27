RootView = require 'views/core/RootView'
template = require 'templates/account/israel-signup-view'
forms = require 'core/forms'
errors = require 'core/errors'
utils = require 'core/utils'
User = require 'models/User'

class AbortError extends Error

formSchema =
  type: 'object'
  properties: _.pick(User.schema.properties, 'name', 'password')
  required: ['name', 'password']


module.exports = class IsraelSignupView extends RootView
  id: 'israel-signup-view'
  template: template
  
  events:
    'submit form': 'onSubmitForm'
    'input input[name="name"]': 'onChangeName'
    'input input[name="password"]': 'onChangePassword'
    
  initialize: ->
    @state = new Backbone.Model({
      fatalError: null
      # Possible errors:
      #   'signed-in': They are logged in
      #   'missing-input': Required query parameters are not provided
      #   'email-exists': Given email exists in our system
      #   Any other string will be shown directly to user
      
      formError: null
      loading: true
      submitting: false
      queryParams: _.pick(utils.getQueryVariables(),
        'il_id'
        'first_name'
        'last_name'
        'email'
        'school'
        'city'
        'state'
        'district'
      )
      name: ''
      password: ''
    })
    
    { il_id, email } = @state.get('queryParams')
    
    if not me.isAnonymous()
      @state.set({fatalError: 'signed-in', loading: false})
    
    else if not (il_id and email) or not forms.validateEmail(email)
      @state.set({fatalError: 'missing-input', loading: false})
      
    else
      User.checkEmailExists(email)
      .then ({exists}) =>
        @state.set({loading: false})
        if exists
          @state.set({fatalError: 'email-exists'})
          
      .catch =>
        @state.set({fatalError: $.i18n.t('loading_error.unknown'), loading: false})
        
    @listenTo(@state, 'change', _.debounce(@render))

  getRenderData: ->
    c = super()
    return _.extend({}, @state.attributes, c)
    
  onChangeName: (e) ->
    @state.set({name: $(e.currentTarget).val()}, {silent: true})
    
  onChangePassword: (e) ->
    @state.set({password: $(e.currentTarget).val()}, {silent: true})

  displayFormSubmitting: ->
    @$('#create-account-btn').text($.i18n.t('signup.creating')).attr('disabled', true)
    @$('input').attr('disabled', true)

  displayFormStandingBy: ->
    @$('#create-account-btn').text($.i18n.t('login.sign_up')).attr('disabled', false)
    @$('input').attr('disabled', false)
    
  onSubmitForm: (e) ->
    e.preventDefault()
    forms.clearFormAlerts(@$el)
    @state.set('formError', null)
    data = forms.formToObject(e.currentTarget)
    res = tv4.validateMultiple data, formSchema
    if not res.valid
      forms.applyErrorsToForm(@$('form'), res.errors)
      return

    queryParams = @state.get('queryParams')
    @displayFormSubmitting()
    User.checkNameConflicts(data.name)
    .then ({ suggestedName, conflicts }) =>
      nameField = @$('input[name="name"]')
      if conflicts
        suggestedNameText = $.i18n.t('signup.name_taken').replace('{{suggestedName}}', suggestedName)
        forms.setErrorToField(nameField, suggestedNameText)
        throw AbortError
      
      me.set({
        signupQueryParams: queryParams
        firstName: queryParams.first_name or ''
        lastName: queryParams.last_name or ''
      })
      return me.save()
        
    .then =>
      return me.signupWithPassword(
        @state.get('name'),
        queryParams.email,
        @state.get('password')
      )
      
    .then =>
      application.router.navigate('/play', { trigger: true })
      
    .catch (e) =>
      @displayFormStandingBy()
      if e is AbortError
        return
      else
        console.error 'IsraelSignupView form submission Promise error:', e
        @state.set('formError', e.responseJSON?.message or e.message or 'Unknown Error')
