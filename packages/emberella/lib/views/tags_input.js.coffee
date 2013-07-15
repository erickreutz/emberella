#= require ../mixins/style_bindings
#= require ../mixins/focusable_mixin
#= require ../mixins/keyboard_control_mixin
#= require ./flexible_text_field

Emberella = window.Emberella
jQuery = window.jQuery
get = Ember.get
set = Ember.set
typeOf = Ember.typeOf

DEFAULT_DELIMITER = ','
ESCAPE_REG_EXP = /[\-\[\]{}()*+?.,\\\^$|#\s]/g
ESCAPE_REPLACEMENT = '\\$&'

Emberella.TagItemView = Ember.View.extend Ember.StyleBindingsMixin, Emberella.FocusableMixin, Emberella.KeyboardControlMixin,
  tagName: 'span'

  classNames: ['emberella-tag-item']

  styleBindings: ['display']

  tabindex: -1

  content: null

  contentPathBinding: 'parentView.contentPath'

  deleteCharacterBinding: 'parentView.deleteCharacter'

  deleteTitleBinding: 'parentView.deleteTitle'

  templateBinding: 'parentView.template'

  displayContent: Ember.computed ->
    return '' unless (content = get @, 'content')?
    contentPath = get @, 'contentPath'
    get(content, contentPath) ? ''
  .property 'content', 'contentPath'

  display: Ember.computed ->
    if Ember.isEmpty(get(@, 'content')) then 'none' else undefined
  .property 'content'

  sendToParent: (message, arg = @, args...) ->
    return @ unless (parentView = get(@, 'parentView'))
    args = [arg].concat(args)
    parentView[message].apply(parentView, args) if typeOf(parentView[message]) is 'function'
    @

  removeSelf: ->
    @sendToParent('removeTag', get(@, 'content'))

  backspacePressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or shift
    @sendToParent 'cursorAfter'
    @removeSelf()

  deletePressed: Ember.aliasMethod 'backspacePressed'

  rightArrowPressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta
    @sendToParent(if shift then 'focusAfter' else 'cursorAfter')

  leftArrowPressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta
    if shift then @sendToParent('focusBefore') else @sendToParent('moveCursor', @, 0)

  upArrowPressed: (e, alt, ctrl, meta, shift) ->
    @sendToParent('upArrowPressed', e, alt, ctrl, meta, shift)

  downArrowPressed: (e, alt, ctrl, meta, shift) ->
    @sendToParent('downArrowPressed', e, alt, ctrl, meta, shift)

  enterPressed: Ember.aliasMethod 'rightArrowPressed'
  tabPressed: Ember.aliasMethod 'rightArrowPressed'

  keyDown: (e) ->
    e.stopPropagation()
    @_super.apply @, arguments

  keyPress: (e) ->
    @_super(e)
    return if e.isDefaultPrevented()
    @backspacePressed(e, false, e.ctrlKey, e.metaKey, false)

Emberella.TagItemInput = Emberella.FlexibleTextField.extend Emberella.FocusableMixin, Emberella.KeyboardControlMixin,
  placeholder: Ember.computed ->
    if get(@, 'parentView.value') then '' else get(@, 'parentView.placeholder')
  .property 'parentView.placeholder', 'parentView.value'

  paste: (e) -> @_didPaste = true

Emberella.TagsInput = Ember.ContainerView.extend Ember.StyleBindingsMixin, Emberella.FocusableMixin, Emberella.KeyboardControlMixin,
  isTagsInput: true

  _value: null
  _cursor: null

  classNames: ['emberella-tags-input']

  styleBindings: ['width', 'height']

  itemViewClass: Emberella.TagItemView

  inputViewClass: Emberella.TagItemInput

  content: null

  delimiter: null

  tabindex: -1

  width: 'auto'

  height: 'auto'

  placeholder: ''

  deleteCharacter: 'x'

  deleteTitle: "Remove tag"

  tagOnFocusOut: true

  contentPath: ''

  defaultTemplate: Ember.Handlebars.compile [
    '<span class="emberella-tag-item-content">{{view.displayContent}}</span>'
    '{{#if view.deleteCharacter}}'
      '<a href="#" {{bindAttr title="view.deleteTitle"}} {{action "removeSelf" target=view bubbles=false}}>{{view.deleteCharacter}}</a>'
    '{{/if}}'
  ].join(' ')

  _primary_delimiter: Ember.computed ->
    delimiter = get(@, 'delimiter') || DEFAULT_DELIMITER
    delimiter = get(delimiter, '0')
    if typeOf(delimiter) is 'string' then delimiter else DEFAULT_DELIMITER
  .property('delimiter', 'delimiter.length').volatile().readOnly()

  _delimiter: Ember.computed ->
    delimiter = get(@, 'delimiter') || DEFAULT_DELIMITER

    if typeOf(delimiter) is 'string' or typeOf(delimiter) is 'number'
      delimiter = (delimiter + '').split('')

    if Ember.isArray(delimiter)
      delimiter = Ember.A(delimiter.slice()).map((item) =>
        if typeOf(item) is 'string' or typeOf(item) is 'number'
          return @_escapeString(item.toString())
        else if typeOf(item) is 'regexp'
          return item.toString().split('/').slice(1, -1).join('/')
        null
      ).compact()

    delimiter = Ember.A(@_escapeString(DEFAULT_DELIMITER)) unless Ember.isArray(delimiter)
    delimiter.join('|')
  .property('delimiter', 'delimiter.length').readOnly()

  _delimiter_pattern: Ember.computed ->
    new RegExp(get(@, '_delimiter'), 'g')
  .volatile().readOnly()

  value: Ember.computed (key, value) ->
    delimiter = get(@, '_primary_delimiter')
    contentPath = get(@, 'contentPath')

    #getter
    if arguments.length is 1
      @_contentToValues()

    #setter
    else
      @addTags(value) if get(@, '_value')?
      set(@, '_value', value)
      return @
  .property('content.length', 'content').volatile()

  cursor: Ember.computed (key, value) ->
    delimiter = get(@, 'delimiter')
    #getter
    if arguments.length is 1
      result = get(@, '_cursor')
      contentLength = get(@, 'content.length')
      return contentLength unless result?
      result = Math.max(0, Math.min(parseInt(result, 10), contentLength))
      return result

    #setter
    else
      set(@, '_cursor', value)
  .property('_cursor').volatile()

  init: ->
    ret = @_super()
    set(@, 'content', get(@, 'content') ? Ember.A())
    @addTags(get(@, '_value') ? '')
    @_renderList()

    ret

  contains: (value) ->
    content = get(@, 'content')
    return false unless content?
    return true if content.contains value
    contentPath = get @, 'contentPath'

    match = content.find((obj) ->
      value is get(obj, contentPath)
    )
    !!(match)

  addTag: (value = '', idx = get(@, 'cursor')) ->
    return false if @contains(value = jQuery.trim(value)) or value is ''
    return @addTags(value) if get(@, '_delimiter_pattern').test(value)

    return false if @didAddValue(value, idx) is false

    set(@, 'cursor', idx + 1)
    true

  addTags: (value = get(@, 'inputView.value'), retainFocus = @_hasFocus()) ->
    delimiter = get @, '_delimiter_pattern'
    values = value.split delimiter
    captured = false

    @beginPropertyChanges()

    for v in values
      captured = true if @addTag(v)

    if captured
      Ember.run.scheduleOnce('afterRender', @, ->
        @reset()
        @_focusOnInputView(retainFocus)
      )

    @endPropertyChanges()
    captured

  removeTag: (value) ->
    return @ unless value?

    content = get(@, 'content')
    idx = content.indexOf value

    return @ if idx < 0

    content.removeObject value
    set(@, 'cursor', idx)
    @didRemoveValue value

  getItemViewClass: ->
    itemViewClass = get @, 'itemViewClass'
    itemViewClass = get(itemViewClass) if typeof itemViewClass is 'string'
    itemViewClass

  getInputViewClass: ->
    inputViewClass = get @, 'inputViewClass'
    inputViewClass = get(inputViewClass) if typeof inputViewClass is 'string'
    inputViewClass

  isItemView: (view) ->
    !!(view instanceof @getItemViewClass())

  isInputView: (view) ->
    !!(view instanceof @getInputViewClass())

  focusOn: (idx) ->
    childViews = get(@, 'childViews')
    viewToFocus = childViews.objectAt idx
    viewToFocus = get(childViews, 'lastObject') unless viewToFocus?
    @moveFocus viewToFocus, 0

  focusBefore: (view) ->
    @moveFocus view, -1

  focusAfter: (view) ->
    @moveFocus view

  moveFocus: (view, shift = 1) ->
    return @ unless view?
    childViews = get(@, 'childViews')
    idx = childViews.indexOf view

    firstView = get(childViews, 'firstObject')
    lastView = get(childViews, 'lastObject')

    viewToFocus = childViews.objectAt(Math.max(0, Math.min(childViews.length - 1, idx + shift)))
    viewToFocus = lastView unless viewToFocus?

    if @isInputView viewToFocus
      if viewToFocus is firstView
        viewToFocus = childViews.objectAt(1) ? viewToFocus
      else if viewToFocus is lastView
        viewToFocus = childViews.objectAt(childViews.length - 1) ? viewToFocus
      else
        idx = childViews.indexOf viewToFocus
        viewToFocus = childViews.objectAt(idx + (shift/Math.abs(shift)))

    get(viewToFocus, 'element').focus()
    @

  cursorBefore: (view) ->
    @moveCursor view, -1

  cursorAfter: (view) ->
    @moveCursor view

  moveCursor: (view, shift = 1) ->
    return @ unless view?
    cursor = get(@, 'cursor')
    childViews = get(@, 'childViews')
    idx = childViews.indexOf view
    shift = shift - 1 if idx > cursor
    set(@, 'cursor', idx + shift)
    @_focusOnInputView(true, (shift < 0))
    @

  focus: (e, beginning = false) ->
    inputView = get @, 'inputView'
    return @ unless inputView? and get(inputView, 'state') is 'inDOM'
    element = get(inputView, 'element')
    element?.focus()
    selection = if beginning then 0 else get(inputView, 'value.length')
    element.selectionStart = selection
    element.selectionEnd = selection
    @

  reset: ->
    set @, 'inputView.value', ''
    @

  isSelectionAtStart: ->
    inputView = get @, 'inputView'
    return @ unless inputView? and get(inputView, 'state') is 'inDOM'
    element = get(inputView, 'element')
    !!(element.selectionStart is 0 and element.selectionEnd is 0)

  isSelectionAtEnd: ->
    inputView = get @, 'inputView'
    return @ unless inputView? and get(inputView, 'state') is 'inDOM'
    element = get(inputView, 'element')
    len = get(inputView, 'value.length')
    !!(element.selectionStart is len and element.selectionEnd is len)

  insertContent: (value, idx) ->
    get(@, 'content').insertAt idx, value

  didAddValue: Ember.aliasMethod 'insertContent'

  didRemoveValue: Ember.K

  click: (e) ->
    return unless e.target is get(@, 'element')
    posX = e.pageX
    posY = e.pageY
    nearest = @.find((childView) ->
      jQ = childView.$()
      position = jQ.offset()
      height = jQ.outerHeight(true)
      space = jQ.outerWidth(true) - jQ.width()
      !!((position.left > (posX - space) and (position.top + height) > posY) or position.top > posY)
    )
    idx = @indexOf(nearest)
    idx = idx - 1 if idx > get(@, 'cursor')
    set(@, 'cursor', if nearest then idx else get(@, 'content.length'))
    @_focusOnInputView(true)

  enterPressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or shift
    e.preventDefault()
    @addTags()

  backspacePressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or shift or !@isSelectionAtStart() or !(inputView = get(@, 'inputView'))
    e.preventDefault()
    @focusBefore(inputView)

  deletePressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or shift or !@isSelectionAtEnd() or !(inputView = get(@, 'inputView'))
    e.preventDefault()
    @focusAfter(inputView)

  rightArrowPressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or !@isSelectionAtEnd() or !(inputView = get(@, 'inputView'))
    e.preventDefault()
    if shift then @focusAfter(inputView) else (@addTags() || @cursorAfter(inputView))

  leftArrowPressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or !@isSelectionAtStart() or !(inputView = get(@, 'inputView'))
    e.preventDefault()
    if shift then @focusBefore(inputView) else @cursorBefore(inputView)

  upArrowPressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or !(inputView = get(@, 'inputView')) or (get(inputView, 'value') isnt '')
    e.preventDefault()
    @cursorBefore(get(@, 'childViews.firstObject'))

  downArrowPressed: (e, alt, ctrl, meta, shift) ->
    return if alt or ctrl or meta or !(inputView = get(@, 'inputView')) or (get(inputView, 'value') isnt '')
    e.preventDefault()
    @cursorAfter(get(@, 'childViews.lastObject'))

  didInputValueChange: Ember.observer ->
    inputView = get(@, 'inputView')
    value = get(inputView, 'value')

    delimiter = get @, '_delimiter_pattern'
    regexString = delimiter.toString().split('/').slice(1, -1).join('/')
    regexString = ['.+(', regexString, ')$'].join('')
    pattern = new RegExp(regexString, 'g')

    @addTags(value) if delimiter.test(value) and (pattern.test(value) or inputView._didPaste)
    inputView._didPaste = false
  , 'inputView.value'

  _cursorDidChange: Ember.observer ->
    @_updateChildViews()
  , 'cursor'

  _delimiterDidChange: Ember.observer ->
    content = get(@, 'content')
    @addTags @_contentToValues()
  , 'delimiter'

  _contentToValues: ->
    content = get @, 'content'
    delimiter = get @, '_primary_delimiter'
    contentPath = get @, 'contentPath'

    if Ember.isArray content
      content = content.map((item) ->
        if item? and (ret = get(item, contentPath)) then ret else item
      ).compact()

    return if (content and content.join) then content.join(delimiter) else get(@, '_value')

  _focusDidChange: Ember.observer ->
    set @, 'hasFocus', @_hasFocus()
  , '@each.hasFocus'

  _hasFocusDidChange: Ember.observer ->
    if !get(@, 'hasFocus')
      # The field may appear to lose focus frequently as the focus shifts
      # between child views. The run later helps to verify the focus has, in
      # fact, completely left the field.
      Ember.run.later @, ->
        return unless get(@, 'state') is 'inDOM' and !@_hasFocus()
        @addTags() if get(@, 'tagOnFocusOut')
        set(@, 'cursor', get(@, 'childViews.length')) if get(@, 'inputView.value') is ''
      , 100
  , 'hasFocus'

  _renderList: ->
    Ember.run.schedule 'afterRender', @, ->
      @_updateChildViews()

  _rerenderList: ->
    @destroyAllChildren()
    @_renderList()

  _hasFocus: ->
    focused = @find((childView) ->
      get(childView, 'hasFocus')
    )
    return !!(focused)

  _focusOnInputView: (force, beginning) ->
    inputView = get(@, 'inputView')

    return unless force or @_hasFocus()

    if get(inputView, 'state') is 'inDOM'
      @focus({}, beginning)
    else
      Ember.run.schedule 'afterRender', @, ->
        @focus({}, beginning) if force or @_hasFocus()

  _insertInputView: ->
    inputView = get(@, 'inputView')
    inputView = if inputView and !get(inputView, 'isDestroyed') and !get(inputView, 'isDestroying') then inputView else @_createInputView()
    cursor = get @, 'cursor'
    @insertAt(cursor, inputView)
    null

  _removeInputView: ->
    inputView = get(@, 'inputView')
    inputView = if inputView and !get(inputView, 'isDestroyed') and !get(inputView, 'isDestroying') then inputView else @_createInputView()
    inputView.removeFromParent()
    null

  _createInputView: ->
    inputView = @createChildView(@getInputViewClass())
    set @, 'inputView', inputView
    inputView

  _updateChildViews: ->
    return if get(@, 'isDestroyed')
    @_removeInputView()

    childViews = @
    childViewsLength = Math.max(0, get(@, 'length'))

    itemViewClass = @getItemViewClass()

    content = get(@, 'content')
    contentLength = get(@, 'content.length')

    for i in [0...Math.max(childViewsLength, contentLength)]
      childView = @objectAt(i)

      if i < contentLength
        unless childView instanceof itemViewClass
          childView = @createChildView(itemViewClass)
          @insertAt(i, childView)
        set childView, 'content', content[i]
      else
        childView?.removeFromParent() if @isItemView childView

    @_insertInputView()
    null

  _escapeString: (str) ->
    str.replace(ESCAPE_REG_EXP, ESCAPE_REPLACEMENT)

  _splitStringByDelimiter: (str = '', result = Ember.A()) ->
    pattern = get(@, '_delimiter_pattern')
    values = str.split(pattern)
    result.clear()

    for v in values
      v = jQuery.trim v
      continue if !v? or v is ''
      result.addObject v

    result

  ################################
  ### CONTENT ARRAY MANAGEMENT ###
  ################################

  ###
    Hook for responding to the content array being replaced with a new
    array instance. Override to add custom handling.

    @method contentWillChange
    @param {Object} self
  ###
  contentWillChange: Ember.K

  ###
    Hook for responding to the content array being replaced with a new
    array instance. Override to add custom handling.

    @method contentDidChange
    @param {Object} self
  ###
  contentDidChange: ->
    @_rerenderList() if get(@, 'state') is 'inDOM'

  ###
    Hook for responding to impending updates to the content array. Override to
    add custom handling for array updates.

    @method contentArrayWillChange
    @param {Array} array The array instance being updated
    @param {Integer} idx The index where changes applied
    @param {Integer} removedCount
    @param {Integer} addedCount
  ###
  contentArrayWillChange: (array, idx, removedCount, addedCount) ->
    @

  ###
    Hook for responding to updates to the content array. Override to
    add custom handling for array updates.

    @method contentArrayDidChange
    @param {Array} array The array instance being updated
    @param {Integer} idx The index where changes applied
    @param {Integer} removedCount
    @param {Integer} addedCount
  ###
  contentArrayDidChange: (array, idx, removedCount, addedCount) ->
    @_updateChildViews()
    @

  ###
    @private

    Content array change handler.

    @method _contentWillChange
  ###
  _contentWillChange: Ember.beforeObserver ->
    content = get(@, 'content')
    len = if content then get(content, 'length') else 0

    @contentArrayWillChange @, 0, len, undefined
    @contentWillChange @
    @_teardownContent content
  , 'content'

  ###
    @private

    Content array change handler.

    @method _contentDidChange
  ###
  _contentDidChange: Ember.observer ->
    content = get(@, 'content')
    len = if content then get(content, 'length') else 0

    @_setupContent content
    @contentDidChange @
    @contentArrayDidChange @, 0, undefined, len
  , 'content'

  ###
    @private

    Remove change observing on content array.

    @method _teardownContent
  ###
  _teardownContent: ->
    @_clearContent()
    content = get(@, 'content')
    if content
      content.removeArrayObserver @,
        willChange: 'contentArrayWillChange',
        didChange: 'contentArrayDidChange'

  ###
    @private

    Begin change observing on content array.

    @method _setupContent
  ###
  _setupContent: ->
    content = get(@, 'content')
    if content
      content.addArrayObserver @,
        willChange: 'contentArrayWillChange',
        didChange: 'contentArrayDidChange'

  ###
    @private

    Empty the content array.

    @method _clearContent
  ###
  _clearContent: ->
    content = get(@, 'content')
    content.clear() if content
