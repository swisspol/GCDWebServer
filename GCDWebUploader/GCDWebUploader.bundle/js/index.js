/*
 Copyright (c) 2012-2014, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

var _path = null;

function formatFileSize(bytes) {
  if (bytes >= 1000000000) {
    return (bytes / 1000000000).toFixed(2) + ' GB';
  }
  if (bytes >= 1000000) {
    return (bytes / 1000000).toFixed(2) + ' MB';
  }
  return (bytes / 1000).toFixed(2) + ' KB';
}

function _showError(message, textStatus, errorThrown) {
  $("#alerts").prepend(tmpl("template-alert", {
    level: "danger",
    title: (errorThrown != "" ? errorThrown : textStatus) + ": ",
    description: message
  }));
}

function _reload(path) {
  $.ajax({
    url: 'list',
    type: 'GET',
    data: {path: path},
    dataType: 'json'
  }).fail(function(jqXHR, textStatus, errorThrown) {
    _showError("Failed retrieving contents of \"" + path + "\"", textStatus, errorThrown);
  })
  .done(function(result) {
    
    if (path != _path) {
      $("#path").empty();
      if (path == "/") {
        $("#path").append('<li class="active">' + _device + '</li>');
      } else {
        $("#path").append('<li data-path="/"><a>' + _device + '</a></li>');
        var components = path.split("/").slice(1, -1);
        for (var i = 0; i < components.length - 1; ++i) {
          var subpath = "/" + components.slice(0, i + 1).join("/") + "/";
          $("#path").append('<li data-path="' + subpath + '"><a>' + components[i] + '</a></li>');
        }
        $("#path > li").click(function(event) {
          _reload($(this).attr("data-path"));
          event.preventDefault();
        });
        $("#path").append('<li class="active">' + components[components.length - 1] + '</li>');
      }
      _path = path;
    }
    
    $("#listing").empty();
    for (var i = 0, file; file = result[i]; ++i) {
      $("#listing").append(tmpl("template-listing", file));
    }
    
    $(".edit").editable(function(value, settings) { 
      var name = $(this).parent().parent().attr("data-name");
      if (value != name) {
        var path = $(this).parent().parent().attr("data-path");
        $.ajax({
          url: 'move',
          type: 'POST',
          data: {oldPath: path, newPath: _path + value},
          dataType: 'json'
        }).fail(function(jqXHR, textStatus, errorThrown) {
          _showError("Failed moving \"" + path + "\" to \"" + _path + value + "\"", textStatus, errorThrown);
        }).always(function() {
          _reload(_path);
        });
      }
      return value;
    }, {
      width: 200,
      tooltip: 'Click to rename...'
    });
    
    $(".button-download").click(function(event) {
      var path = $(this).parent().parent().attr("data-path");
      setTimeout(function() {
        window.location = "download?path=" + encodeURIComponent(path);
      }, 0);
    });
    
    $(".button-open").click(function(event) {
      var path = $(this).parent().parent().attr("data-path");
      _reload(path);
    });
    
    $(".button-delete").click(function(event) {
      var path = $(this).parent().parent().attr("data-path");
      $.ajax({
        url: 'delete',
        type: 'POST',
        data: {path: path},
        dataType: 'json'
      }).fail(function(jqXHR, textStatus, errorThrown) {
        _showError("Failed deleting \"" + path + "\"", textStatus, errorThrown);
      }).always(function(result) {
        _reload(_path);
      });
    });
    
  });
}

$(document).ready(function() {
  
  $("#fileupload").fileupload({
    dropZone: $(document),
    pasteZone: null,
    autoUpload: true,
    sequentialUploads: true,
    // limitConcurrentUploads: 2,
    // forceIframeTransport: true,
    
    url: 'upload',
    type: 'POST',
    dataType: 'json',
    
    start: function(e) {
      $("#progress-bar").css("width", "0%");
      $(".uploading").show();
    },
    
    progressall: function(e, data) {
      var progress = parseInt(data.loaded / data.total * 100, 10);
      $("#progress-bar").css("width", progress + "%");  // .text(progress + "%")
    },
    
    stop: function(e) {
      $(".uploading").hide();
    },
    
    add: function(e, data) {
      
      $(".uploading").show();
      
      var file = data.files[0];
      data.formData = {
        path: _path
      };
      data.context = $(tmpl("template-uploads", {
        path: _path + file.name
      })).appendTo("#uploads");
      var jqXHR = data.submit();
      data.context.find("button").click(function(event) {
        jqXHR.abort();
      });
    },
    
    progress: function(e, data) {
      var progress = parseInt(data.loaded / data.total * 100, 10);
      data.context.find(".progress-bar").css("width", progress + "%");
    },
    
    done: function(e, data) {
      _reload(_path);
    },
    
    fail: function(e, data) {
      var file = data.files[0];
      if (data.errorThrown != "abort") {
        _showError("Failed uploading \"" + file.name + "\" to \"" + _path + "\"", data.textStatus, data.errorThrown);
      }
    },
    
    always: function(e, data) {
      data.context.remove();
    },
    
  });
  
  $("#create-folder").click(function(event) {
    var name = prompt("Please enter folder name:", "Untitled folder");
    if ((name != null) && (name != "")) {
      $.ajax({
        url: 'create',
        type: 'POST',
        data: {path: _path + name},
        dataType: 'json'
      }).fail(function(jqXHR, textStatus, errorThrown) {
        _showError("Failed creating folder \"" + name + "\" in \"" + _path + "\"", textStatus, errorThrown);
      }).always(function(result) {
        _reload(_path);
      });
    }
  });
  
  $("#reload").click(function(event) {
    _reload(_path);
  });
  
  _reload("/");
  
});
