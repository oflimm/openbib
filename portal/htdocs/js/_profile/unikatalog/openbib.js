var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
  return new bootstrap.Tooltip(tooltipTriggerEl)
})

function imagePreview (){
  /* CONFIG */
  
  xOffset = 10;
  yOffset = 30;
  
  // these 2 variable determine popup's distance from the cursor
  // you might want to adjust to get the right result
  
  /* END CONFIG */
  $("a.ob-preview").hover(function(e){
			 var t = this.title;
			 var c = (t != "") ? "<br/>" + t : "";
			 $("body").append("<p id='preview'><img src='"+ this.href +"' alt='Image preview' />"+ c +"</p>"); 
			 $("#preview")
			   .css("top",(e.pageY - yOffset) + "px")
			   .css("left",(e.pageX + xOffset) + "px")
			   .fadeIn("fast");
		       },
		       function(){
			 this.title = this.t;
			 $("#preview").remove();
		       });
  $("a.ob-preview").mousemove(function(e){
			     $("#preview")
			       .css("top",(e.pageY - yOffset) + "px")
			       .css("left",(e.pageX + xOffset) + "px");
			   });
};

function openMsgWin(URL,name,width,height,scrollbars,otherbars) {
  if( ! width  ) { width  = window.outerWidth  || document.documentElement.clientWidth  || screen.width  };
  if( ! height ) { height = window.outerHeight || document.documentElement.clientHeight || screen.height };
  width  = width*85/100;
  height = height*75/100;
  if( ! scrollbars ) { scrollbars = 'yes' };
  if( ! otherbars  ) { otherbars  = 'yes' };
  var Win = window.open(URL,name,"width="+width+",height="+height+",top=75,left=100,scrollbars="+scrollbars+",resizable=yes,menubar="+otherbars+",toolbar="+otherbars);
  Win.focus();
}

function qrcodeShow () {
  /* CONFIG: distance of the popup from the cursor */
  var xOffset = 15;
  var yOffset = -25;
  /* END CONFIG */
    
  $("a.ob-qrcode_preview").click(function(e) {
    $("body").append("<p id=\"ob-qrcode\"><strong>QR-Code</strong> &nbsp; [ <a class=\"ext\" href=\"http://qrcode.wilkohartz.de/\" onclick=\"openMsgWin('','QR-Code Informationen','','','yes','yes');return true;\" target=\"QR-Code Informationen\">Reader-Software</a> ]<img src=\"/images/openbib/close.png\" alt=\"Schließen\" title=\"Schließen\" class=\"ob-closebutton\" /><br/ ><img src=\""+ this.href +"\" alt=\"QR-Code\" style=\"margin:5px 0 5px 0;\" /><br/>" + this.title + "</p>"); 
    $("#ob-qrcode")
      .css("top",(e.pageY - yOffset) + "px")
      .css("left",(e.pageX + xOffset) + "px")
      .fadeIn("fast");
    qrcodeRemove();
  });
};

function qrcodeRemove () {
  $(".ob-closebutton").click(function(e) {
    $("#ob-qrcode").remove();
  });
};

// $(document).ready(function(){
$(function(){

//  $(document).on('change', '.selectpicker', function(e){
//    e.preventDefault();
//
//    window.location = $(this).find('option:selected').val();
//  });
    
    // var Bibkey    = $("meta[@name='Bibkey']").attr("content");
    // var Tags      = $("meta[@name='Tags']").attr("content");
    // var View      = $("meta[@name='View']").attr("content");

  // Activate accessible tabs
// $("#searchform_types").accessibleTabs({ tabbody: '.tabbody', tabhead: 'h3', fxspeed: 'fast', syncheights: true });

 $('.selectpicker').selectpicker();
 imagePreview();
 qrcodeShow();


 $('#ob-simplesearch_reset').click(function() {
                                     $('#to_focus').focus();
                                   });

 // Focus auf erstes Eingabefeld
  $(":input:visible:enabled:first").focus();
  //$("input[@id='to_focus']").focus();

// Tabs fuer weitere Informationen
 //$('#ob-additional_title_info > ul').tabs();


function resizeScreen(){
  if ($(window).width() < 750){
    $("#ob-facets_all_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-facets_all_toggle").click(function(){
        $("#ob-facets_all_toggle_do").toggle();
     });

    $("#ob-reuse_508_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-reuse_508_toggle").click(function(){
        $("#ob-reuse_508_toggle_do").toggle();
     });
      
    $("#ob-reuse_333_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-reuse_333_toggle").click(function(){
        $("#ob-reuse_333_toggle_do").toggle();
     });

    $("#ob-reuse_336_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-reuse_336_toggle").click(function(){
        $("#ob-reuse_336_toggle_do").toggle();
     });

      $("#ob-facets_dbinfo_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-facets_dbinfo_toggle").click(function(){
        $("#ob-facets_dbinfo_toggle_do").toggle();
     });

    $("#ob-record_title_save_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-record_title_save_toggle").click(function(){
        $("#ob-record_title_save_toggle_do").toggle();
     });
       
    $("#ob-record_title_discover_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-record_title_discover_toggle").click(function(){
        $("#ob-record_title_discover_toggle_do").toggle();
     });
       
    $("#ob-record_title_history_toggle_do").hide();
     // und bei Klick Sichtbarkeit togglen
       $("#ob-record_title_history_toggle").click(function(){
        $("#ob-record_title_history_toggle_do").toggle();
     });
  }
  else {
    $("#ob-facets_all_toggle_do").show();
      $("#ob-reuse_508_toggle_do").show();
      $("#ob-reuse_333_toggle_do").show();
      $("#ob-reuse_336_toggle_do").show();
    $("#ob-facets_dbinfo_toggle_do").show();
    $("#ob-record_title_save_toggle_do").show();
    $("#ob-record_title_discover_toggle_do").show();
    $("#ob-record_title_history_toggle_do").show();
  }
/*
  if($(window).width() > 880){
   // Tabs fuer Suchmaske nach Formaten 
   $('#ob-searchform_types').tabs();
   
   // Tabs fuer Login nach Ziel   
   $('#ob-login_forms').tabs();

   // Tabs fuer weitere Informationen
   $('#ob-additional_title_info').tabs();
  }
  else {
   // Tabs fuer Suchmaske nach Formaten 
   $('#ob-searchform_types').tabs("destroy");
   
   // Tabs fuer Login nach Ziel   
   $('#ob-login_forms').tabs("destroy");

   // Tabs fuer weitere Informationen
   $('#ob-additional_title_info').tabs("destroy");
  }
*/
}


// event handler for window resize
$(window).resize(function(e){
  resizeScreen();
});
resizeScreen();

// Accordion fuer Datenbankauswahl
//$('.ui-accordion').accordion({ 
//      autoHeight: false,
//      alwaysOpen: false, 
//});

// nojs_* modifizieren fuer JavaScript-Version der Seite

$('.ob-nojs_hidden').css('display','block');
$('.ob-nojs_show').css('display','none');

$('select.autosubmit').change(function(){
                                       this.form.submit();
                                     });
 
 // Begin Merkliste
// Merklistenfuellstand aktualisieren
// Achtung!!! Wert von managecollection_loc aus OpenBib::Config ist hier
// fest eingetragen und muss gegebenenfalls angepasst werden

//    if (View){
// $.get("/portal/"+View+"/collection/count",
// function (txt){
//  $("#collectioncount").html("["+txt+"]"); 
// }
// );
//    }
//    else {
//      $.get("/portal/collection/count",
// function (txt){
//  $("#collectioncount").html("["+txt+"]"); 
// }
// );

//    }

 $(".ob-collection").click(function(){


   // Insert-Funktion aufrufen
   $.get(this.href);

   // Signalisieren, dass in Merkliste transferiert wurde
   $(this).children("img").attr("src","/images/openbib/material/ic_star_24px.svg");

   // Merklistenfuellstand aktualisieren
   //  $.get("[% path_prefix %]/[% IF user.ID %][% config.get('users_loc') %]/id/[% user.ID %]/[% END %][% config.get('cartitems_loc') %]/count",
   //function (txt){ $("#ob-collectioncount").html("["+txt+"]"); });

   return false;
 });

// Ende Merkliste

// Begin BibSonomy Tags
//  if (Bibkey || Tags){
//    if (View){
//    $.get("/portal/"+View+"/bibsonomy/lookup?format=ajax;bibkey="+Bibkey+";tags="+Tags,
//          function (txt){
//            $("#bibsonomy_tags").html(txt); 
//          }
//          );
//    }
//    else {
//    $.get("/portal/bibsonomy/lookup?format=ajax;bibkey="+Bibkey+";tags="+Tags,
//          function (txt){
//            $("#bibsonomy_tags").html(txt); 
//          }
//          );
//    }
//  }

 // $(document).ready(function(){

//$("#bibsonomy_tags a").click(function(){

//  $.get("/portal/bibsonomy?sessionID="+sessionID+";action=get_tags;titisbn="+ISBN,
//   function (xml){
//        $(xml).find('bibsonomy_tags').each(function(){
//        var item_text = $(this).text();

//        $("<li></li>")
//            .html(item_text)
//            .appendTo('ol');
//    });
//   }
//   return false;
// });
// Ende  BibSonomy Tags
// --------------------------------------------------------------------------

// Begin Togglen
// Zuerst verstecken
$(".ob-fieldset").hide();
// und bei Klick Sichtbarkeit togglen
$(".ob-toggable_legend").click(function(){
   $(".ob-fieldset").toggle();
});
 
// // Begin Togglen / Suchhilfe
// // Zuerst verstecken
// $("#searchinfo").hide();
// // und bei Klick Sichtbarkeit togglen
// $("#searchinfo_toggle").click(function(){
//  $("#searchinfo").toggle();
// });
// // Ende Togglen / Suchhilfe

// // --------------------------------------------------------------------------

// // Begin Togglen / Suchoptionen
// // Zuerst verstecken
// $("#searchoptions").hide();
// // und bei Klick Sichtbarkeit togglen
// $("#searchoptions_toggle").click(function(){
//  $("#searchoptions").toggle();
// });
// // Ende Togglen / Suchoptionen

// // --------------------------------------------------------------------------

// // Begin Togglen / Eigene Tags
// // Bild setzen
// $("#newtags_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Tag-Eingabe anzeigen\">")
// // Zuerst verstecken
// $("#newtags").hide();
// // und bei Klick Sichtbarkeit togglen
// $("#newtags_toggle").click(function(){
//  $("#newtags").toggle();
// });
// // Ende Togglen / Eigene Tags

// // --------------------------------------------------------------------------

// // Begin Togglen / 'Gleiche Titel' (=gleiche ISBN) in anderen Katalogen
// // Bild setzen
// $("#samerecord_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Tag-Eingabe anzeigen\">")
// // Zuerst verstecken
// $("#samerecord").hide();
// // und bei Klick Sichtbarkeit togglen
// $("#samerecord_toggle").click(function(){
//  $("#samerecord").toggle();
// });
// // Ende Togglen / Eigene Tags

// // --------------------------------------------------------------------------
// // Begin Togglen / 'Aehnliche Titel' (via LibraryThing) im KUG
// // Bild setzen
// $("#similarrecord_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Tag-Eingabe anzeigen\">")
// // Zuerst verstecken
// $("#similarrecord").hide();
// // und bei Klick Sichtbarkeit togglen
// $("#similarrecord_toggle").click(function(){
//  $("#similarrecord").toggle();
// });
// // Ende Togglen / Eigene Tags

// --------------------------------------------------------------------------
// Begin Togglen / Eigene Reviews
// Zuerst verstecken
$("#ob-newreview_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-newreview_toggle").click(function(){
 $("#ob-newreview_do").toggle();
});
// Ende Togglen / Eigene Reviews

// --------------------------------------------------------------------------

 
// Begin Togglen / Alle Reviews
// Zuerst verstecken
$("#ob-allreviews_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-allreviews_toggle").click(function(){
 $("#ob-allreviews_do").toggle();
});
// Ende Togglen / alle Reviews

// Begin Togglen / Formate
// Zuerst verstecken
$("#ob-formats_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-formats_toggle").click(function(){
 $("#ob-formats_do").toggle();
});
// Ende Togglen / Formate

// Begin Togglen / Verwandte Personen
// Zuerst verstecken
$("#ob-similar_persons_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-similar_persons_toggle").click(function(){
 $("#ob-similar_persons_do").toggle();
});
// Ende Togglen / Verwandte Personen

// Begin Togglen / Verwandte Themen
// Zuerst verstecken
$("#ob-similar_subjects_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-similar_subjects_toggle").click(function(){
 $("#ob-similar_subjects_do").toggle();
});
// Ende Togglen / Verwandte Personen

// Begin Togglen / BibSonomy Tags
// Zuerst verstecken
$("#ob-bibsonomy_tags_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-bibsonomy_tags_toggle").click(function(){
 $("#ob-bibsonomy_tags_do").toggle();
});
// Ende Togglen / BibSonomy_tags

// Begin Togglen / Verschiedenes
// Zuerst verstecken
$("#ob-misc_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-misc_toggle").click(function(){
 $("#ob-misc_do").toggle();
});
// Ende Togglen / Verschiedenes

// Begin Togglen / Literaturlisten
// Zuerst verstecken
$("#ob-litlists_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-litlists_toggle").click(function(){                              
  $("#ob-litlists_do").toggle();
});
// Ende Togglen / Literaturlisten

// Begin Togglen / Tagging
// Zuerst verstecken
$("#ob-tagging_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#ob-tagging_toggle").click(function(){
 $("#ob-tagging_do").toggle();
});
// Ende Togglen / Tagging


 
  });

//$(window).load(function(){
//    $(window).scroll(function(){
//        if($(window).scrollTop()>110){
//            $('#ob-fixed_navigation').css('position', 'fixed');
//            $('#ob-fixed_navigation').css('top', 0);
//            $('#ob-fixed_navigation').css('margin-left', '60px');
//        } else {
//            $('#ob-fixed_navigation').css('position', 'relative');
//            $('#ob-fixed_navigation').css('margin', '0px 60px 0px');
//        }
//    });
//});


  
function insert_tag(event,id) {

  var this_element = "";
  
  if (!event)
    event = window.event;

  if (event.srcElement) {
    // Der Internet Explorer verwendet srcElement
    this_element = event.srcElement;
  }
  else if (event.target) {
    // Mozilla und Abkoemmlinge verwenden target
    this_element = event.target;
  }
  
  var tag  = this_element.childNodes[0].nodeValue;

  tag = tag.replace(/ /,"");
  
  var this_input = document.getElementById(id);
  
  var tags = this_input.value.split(" ");
  
  if (tags[0] == "") {
    tags.splice(0,1);
  }
  
  var done = 0;
  var new_tags = new Array();
  
  for (var i = 0; i < tags.length; i++) {
    var this_tag = tags[i];
    if (tag == this_tag) {
      done = 1;
    }
    else {
      new_tags.push(this_tag);
    }
  }
      
  if (!done) {
    new_tags.push(tag) ;
  }
  
  var new_input = new_tags.join(" ");
  this_input.value = new_input;
  
  this_input.focus();
}


