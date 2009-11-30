#--
# Copyright (c) 2005-2009, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++


require 'ruote/engine/context'
require 'ruote/queue/subscriber'


module Ruote

  #
  # Encapsulating all the information about an error in a process instance.
  #
  class ProcessError

    def initialize (h)
      @h = h
    end

    def at
      @h[:at]
    end

    # The 'internal' workqueue event
    #
    def msg
      @h[:message]
    end

    def direction
      msg[1]
    end

    def fei
      msg.last[:fei]
    end

    def wfid
      fei.wfid
    end

    def tree
      msg.last[:tree]
    end

    def workitem
      msg.last[:workitem]
    end

    def error_class
      @h[:error][0]
    end
    def error_message
      @h[:error][1]
    end
    def error_backtrace
      @h[:error][2]
    end

    # A shortcut for modifying the tree of an expression when it has had
    # an error upon being applied.
    #
    def tree= (t)

      raise "no tree in error, can't override" unless tree
      msg.last[:tree] = t
    end

    def to_h (short=false)

      h = {}
      h['fei'] = fei.to_h
      h['error'] = @h[:error][0, 2] + [ @h[:error][2].first ]
      h['direction'] = direction.to_s

      return h if short

      h['workitem'] = workitem.to_h
      h['tree'] = tree

      h
    end
  end

  #
  # Keeping track of the errors plaguing processes.
  #
  class HashErrorJournal

    include EngineContext
    include Subscriber

    def context= (c)

      @errors = {}
      @context = c

      subscribe(:errors)
    end

    # Returns the list of errors for a given process instance
    #
    def process_errors (wfid)

      (@errors[wfid] || {}).values.collect { |e| ProcessError.new(e) }
    end

    def replay_at_error (err)

      remove(err.fei)
      wqueue.emit(*err.msg)
    end

    # Removes the errors corresponding to a process.
    #
    # Returns true if there was actually some errors that got purged.
    #
    def purge_process (wfid)

      (@errors.delete(wfid) != nil)
    end

    # Removes all the errors whose process is not active anymore.
    #
    def purge_processes

      @errors.keys.each do |wfid|
        exps = expstorage.find_expressions(:wfid => wfid)
        purge_process(wfid) if exps.size < 1
      end
    end

    # Clears all errors. Mostly used by the test framework.
    #
    def purge!

      @errors.clear
    end

    protected

    def record (fei, eargs)

      (@errors[fei.parent_wfid] ||= {})[fei] = eargs
    end

    def remove (fei)

      if errs = @errors[fei.parent_wfid]
        errs.delete(fei)
      end
    end

    def receive (eclass, emsg, eargs)

      if emsg == :remove
        remove(eargs[:fei])
        return
      end

      eargs = eargs.dup

      info = eargs[:message].last

      fei = info[:fei] || (info[:expression] || info[:workitem]).fei
      wfid = info[:wfid]

      err = eargs[:error]
      eargs[:error] = [ err.class.name, err.message, err.backtrace ]
        # since Exception#to_yaml is not reliable...

      eargs[:fei] = fei
      eargs[:at] = Time.now

      record(fei, eargs)
    end
  end
end
