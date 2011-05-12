this.imagePreview = function(){
  /* CONFIG */
  
  xOffset = 10;
  yOffset = 30;
  
  // these 2 variable determine popup's distance from the cursor
  // you might want to adjust to get the right result
  
  /* END CONFIG */
  $("a.preview").hover(function(e){
			 this.t = this.title;
			 this.title = "";
			 var c = (this.t != "") ? "<br/>" + this.t : "";
			 $("body").append("<p id='preview'><img src='"+ this.href +"' alt='Image preview' />"+ c +"</p>"); 
			 $("#preview")
			   .css("top",(e.pageY - xOffset) + "px")
			   .css("left",(e.pageX + yOffset) + "px")
			   .fadeIn("fast");
		       },
		       function(){
			 this.title = this.t;
			 $("#preview").remove();
		       });
  $("a.preview").mousemove(function(e){
			     $("#preview")
			       .css("top",(e.pageY - xOffset) + "px")
			       .css("left",(e.pageX + yOffset) + "px");
			   });

  $("a.qrcode").hover(function(e){
			 this.t = this.title;
			 this.title = "";
			 var c = (this.t != "") ? "<br/>" + this.t : "";
			 $("body").append("<p id='qrcode'><img src='"+ this.href +"' alt='Image preview' />"+ c +"</p>"); 
			 $("#qrcode")
			   .css("top",(e.pageY - xOffset) + "px")
			   .css("left",(e.pageX + yOffset) + "px")
			   .fadeIn("fast");
		       },
		       function(){
			 this.title = this.t;
			 $("#qrcode").remove();
		       });
  $("a.qrcode").mousemove(function(e){
			     $("#qrcode")
			       .css("top",(e.pageY - xOffset) + "px")
			       .css("left",(e.pageX + yOffset) + "px");
			   });

};

$(document).ready(function(){

                    
var sessionID = $("meta[@name='sessionID']").attr("content");

var Bibkey    = $("meta[@name='Bibkey']").attr("content");
var Tags      = $("meta[@name='Tags']").attr("content");
var View      = $("meta[@name='View']").attr("content");

imagePreview();
 
// Focus auf erstes Eingabefeld
//$(":input:visible:enabled:first").focus();
$("input[@id='to_focus']").focus();

// Tabs fuer weitere Informationen
$('#additional_title_info > ul').tabs();

// Tabs fuer Suchmaske nach Formaten 
$('#searchform_types > ul').tabs();

// Accordion fuer Datenbankauswahl
$('.ui-accordion').accordion({ 
      autoHeight: false,
      alwaysOpen: false, 
});

// nojs_* modifizieren fuer JavaScript-Version der Seite

$('.nojs_hidden').css('display','block');
$('.nojs_show').css('display','none');

 // Begin Merkliste
// Merklistenfuellstand aktualisieren
// Achtung!!! Wert von managecollection_loc aus OpenBib::Config ist hier
// fest eingetragen und muss gegebenenfalls angepasst werden
 if (sessionID){
$.get("/portal/"+View+"/collection/count",
function (txt){
 $("#collectioncount").html("["+txt+"]"); 
}
);
 }
 
$(".rlcollect a").click(function(){

   // Insert-Funktion aufrufen
   $.get(this.href);

   // Merklistenfuellstand aktualisieren
   $.get("/portal/"+View+"/collection/count",
function (txt){ $("#collectioncount").html("["+txt+"]"); });

   return false;
 });

$("a.collection").click(function(){

   // Insert-Funktion aufrufen
   $.get(this.href);

   // Merklistenfuellstand aktualisieren
   $.get("/portal/"+View+"/collection/count",
function (txt){ $("#collectioncount").html("["+txt+"]"); });

   return false;
 });


// Ende Merkliste

// Begin BibSonomy Tags
 if (Bibkey || Tags){
   $.get("/portal/"+View+"/bibsonomy/lookup?format=ajax;bibkey="+Bibkey+";tags="+Tags,
         function (txt){
           $("#bibsonomy_tags").html(txt); 
         }
         );
 }

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

// Begin Togglen / Suchhilfe
// Zuerst verstecken
$("#searchinfo").hide();
// und bei Klick Sichtbarkeit togglen
$("#searchinfo_toggle").click(function(){
 $("#searchinfo").toggle();
});
// Ende Togglen / Suchhilfe

// --------------------------------------------------------------------------

// Begin Togglen / Suchoptionen
// Zuerst verstecken
$("#searchoptions").hide();
// und bei Klick Sichtbarkeit togglen
$("#searchoptions_toggle").click(function(){
 $("#searchoptions").toggle();
});
// Ende Togglen / Suchoptionen

// --------------------------------------------------------------------------

// Begin Togglen / Eigene Tags
// Bild setzen
$("#newtags_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Tag-Eingabe anzeigen\">")
// Zuerst verstecken
$("#newtags").hide();
// und bei Klick Sichtbarkeit togglen
$("#newtags_toggle").click(function(){
 $("#newtags").toggle();
});
// Ende Togglen / Eigene Tags

// --------------------------------------------------------------------------

// Begin Togglen / 'Gleiche Titel' (=gleiche ISBN) in anderen Katalogen
// Bild setzen
$("#samerecord_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Tag-Eingabe anzeigen\">")
// Zuerst verstecken
$("#samerecord").hide();
// und bei Klick Sichtbarkeit togglen
$("#samerecord_toggle").click(function(){
 $("#samerecord").toggle();
});
// Ende Togglen / Eigene Tags

// --------------------------------------------------------------------------
// Begin Togglen / 'Aehnliche Titel' (via LibraryThing) im KUG
// Bild setzen
$("#similarrecord_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Tag-Eingabe anzeigen\">")
// Zuerst verstecken
$("#similarrecord").hide();
// und bei Klick Sichtbarkeit togglen
$("#similarrecord_toggle").click(function(){
 $("#similarrecord").toggle();
});
// Ende Togglen / Eigene Tags

// --------------------------------------------------------------------------
// Begin Togglen / Eigene Reviews
// Bild setzen
$("#newreview_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Bewertungs/Rezensions-Eingabe anzeigen\">")
// Zuerst verstecken
$("#newreview").hide();
// und bei Klick Sichtbarkeit togglen
$("#newreview_toggle").click(function(){
 $("#newreview").toggle();
});
// Ende Togglen / Eigene Reviews

// --------------------------------------------------------------------------

// Begin Togglen / Alle Reviews
// Zuerst verstecken
$("#allreviews").hide();
// und bei Klick Sichtbarkeit togglen
$("#allreviews_toggle").click(function(){
 $("#allreviews").toggle();
});
// Ende Togglen / alle Reviews

// Begin Togglen / Formate
// Zuerst verstecken
$("#formats_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#formats_toggle").click(function(){
 $("#formats_do").toggle();
});
// Ende Togglen / Formate

// Begin Togglen / Verwandte Personen
// Zuerst verstecken
$("#similarpersons_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#similarpersons_toggle").click(function(){
 $("#similarpersons_do").toggle();
});
// Ende Togglen / Verwandte Personen

// Begin Togglen / Verwandte Themen
// Zuerst verstecken
$("#similarsubjects_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#similarsubjects_toggle").click(function(){
 $("#similarsubjects_do").toggle();
});
// Ende Togglen / Verwandte Personen

// Begin Togglen / BibSonomy Tags
// Zuerst verstecken
$("#bibsonomy_tags_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#bibsonomy_tags_toggle").click(function(){
 $("#bibsonomy_tags_do").toggle();
});
// Ende Togglen / BibSonomy_tags

// Begin Togglen / Verschiedenes
// Zuerst verstecken
$("#misc_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#misc_toggle").click(function(){
 $("#misc_do").toggle();
});
// Ende Togglen / Verschiedenes

// Begin Togglen / Literaturlisten
// Zuerst verstecken
$("#litlists_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#litlists_toggle").click(function(){
 $("#litlists_do").toggle();
});
// Ende Togglen / Literaturlisten

// Begin Togglen / Tagging
// Zuerst verstecken
$("#tagging_do").hide();
// und bei Klick Sichtbarkeit togglen
$("#tagging_toggle").click(function(){
 $("#tagging_do").toggle();
});
// Ende Togglen / Tagging
 
});


function insert_tag(event) {

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
  
  var this_input = document.getElementById('inputfield');
  
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
