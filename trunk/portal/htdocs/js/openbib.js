$(document).ready(function(){

var sessionID = $("meta[@name='sessionID']").attr("content");

var ISBN      = $("meta[@name='ISBN']").attr("content");

// Focus auf erstes Eingabefeld
$(":input:visible:enabled:first").focus();

// Begin Merkliste
// Merklistenfuellstand aktualisieren
// Achtung!!! Wert von managecollection_loc aus OpenBib::Config ist hier
// fest eingetragen und muss gegebenenfalls angepasst werden
$.get("/portal/merkliste?sessionID="+sessionID+";action=show;do_collection_showcount=1",
function (txt){
 $("#collectioncount").html("["+txt+"]"); 
}
);

$(".rlcollect a").click(function(){

   // Insert-Funktion aufrufen
   $.get(this.href);

   // Merklistenfuellstand aktualisieren
   $.get("/portal/merkliste?sessionID="+sessionID+";action=show;do_collection_showcount=1",
function (txt){ $("#collectioncount").html("["+txt+"]"); });

   return false;
 });
// Ende Merkliste

// Begin BibSonomy Tags
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
// Bild setzen
$("#searchinfo_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Suchhilfe anzeigen\">")
// Zuerst verstecken
$("#searchinfo").hide();
// und bei Klick Sichtbarkeit togglen
$("#searchinfo_toggle").click(function(){
 $("#searchinfo").toggle();
});
// Ende Togglen / Suchhilfe

// --------------------------------------------------------------------------

// Begin Togglen / Suchoptionen
// Bild setzen
$("#searchoptions_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Optionen anzeigen\">")
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
// Bild setzen
$("#allreviews_toggle").html("<img src=\"/images/openbib/expand.png\" alt=\"Alle Bewertungen anzeigen\">")
// Zuerst verstecken
$("#allreviews").hide();
// und bei Klick Sichtbarkeit togglen
$("#allreviews_toggle").click(function(){
 $("#allreviews").toggle();
});
// Ende Togglen / alle Reviews
 
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
