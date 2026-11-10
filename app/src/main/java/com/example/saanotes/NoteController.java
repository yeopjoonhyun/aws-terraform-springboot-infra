package com.example.saanotes;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/notes")
public class NoteController {

    private final NoteRepository repository;

    public NoteController(NoteRepository repository) {
        this.repository = repository;
    }

    /** 요청 본문. 입력값 규칙은 표기(애너테이션)로 지정하고 위반하면 400을 돌려준다. */
    public record NoteRequest(
            @NotBlank @Size(max = 100) String title,
            @NotBlank @Size(max = 30) String category,
            @NotBlank @Size(max = 2000) String content) {
    }

    public record NoteResponse(Long id, String title, String category, String content, LocalDateTime createdAt) {

        static NoteResponse from(Note n) {
            return new NoteResponse(n.getId(), n.getTitle(), n.getCategory(), n.getContent(), n.getCreatedAt());
        }
    }

    @GetMapping
    public List<NoteResponse> list(@RequestParam(required = false) String category) {
        List<Note> notes = (category == null)
                ? repository.findAll()
                : repository.findByCategoryOrderByIdDesc(category);
        return notes.stream().map(NoteResponse::from).toList();
    }

    @GetMapping("/{id}")
    public NoteResponse get(@PathVariable Long id) {
        return NoteResponse.from(find(id));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public NoteResponse create(@Valid @RequestBody NoteRequest req) {
        return NoteResponse.from(repository.save(new Note(req.title(), req.category(), req.content())));
    }

    @PutMapping("/{id}")
    @Transactional
    public NoteResponse update(@PathVariable Long id, @Valid @RequestBody NoteRequest req) {
        Note note = find(id);
        note.update(req.title(), req.category(), req.content());
        return NoteResponse.from(note);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        repository.delete(find(id));
    }

    private Note find(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "note not found: " + id));
    }
}
