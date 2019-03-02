#### chunkwm-ffm configuration index

* [config settings](#config-settings)
  * [bypass ffm temporarily](#bypass-ffm-temporarily)
  * [standby on float](#standby-on-float)
  * [always switch on display change](#always-switch-on-display-change)

#### config settings

##### bypass ffm temporarily

    chunkc set ffm_bypass_modifier <option>
    <option>: fn | shift | alt | cmd | ctrl
    desc: arbitrary combination allowed (use whitespace as delimeter).

##### standby on float

    chunkc set ffm_standby_on_float <option>
    <option>: 1 | 0
    desc: temporarily disable ffm when a floating window gets focus

##### always switch on display change

    chunkc set ffm_always_switch_display <option>
    <option>: 1 | 0
    desc: moving cursor to another display will always raise the display
